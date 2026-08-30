#!/bin/sh
# tutrelease -- the tutorial's examples against the compiler a READER
# INSTALLS, which is not the compiler the other gates use.
#
# tutdiff compiles every example with the m9c built from THIS TREE, so
# it proves the tutorial agrees with the compiler as it stands.  But
# chapter 0 tells a reader to install the released package, and
# nothing held the examples to THAT: the day an example uses something
# added after the release, CI stays green and the reader's copy breaks
# with a diagnostic the page does not show.  Measured once by hand on
# 2026-08-30 (11 examples, 5 refusals, all agreeing); this is that
# measurement as a gate, so it keeps being true.
#
# The tarball is the latest release of the PUBLIC compiler repository.
# No network, no release, no fpc-free build -- it SKIPS OUT LOUD, the
# way the zarr and TLS batteries do; a gate that quietly disappears is
# worse than no gate.  $M9RELEASE_TARBALL points it at a local file
# instead (what the by-hand run used).
set -e
cd "$(dirname "$0")"
REPO=$(cd ../.. && pwd)
EXA=$REPO/docs/tutorial/examples
[ -d "$EXA" ] || { echo "SKIP: tutrelease (no docs/tutorial in this tree)"; exit 0; }

W=/tmp/m9tut-release
rm -rf "$W"; mkdir -p "$W/src"

TAR=${M9RELEASE_TARBALL:-}
if [ -z "$TAR" ]; then
  url=$(curl -sSf --max-time 30 \
        https://api.github.com/repos/atverm/m9c/releases/latest 2>/dev/null |
        sed -n 's/.*"browser_download_url": *"\([^"]*m9-[0-9.]*\.tar\.gz\)".*/\1/p' |
        head -1) || url=""
  [ -n "$url" ] || { echo "SKIP: tutrelease (no release tarball reachable)"; exit 0; }
  curl -sSfL --max-time 120 -o "$W/rel.tar.gz" "$url" ||
    { echo "SKIP: tutrelease (the release tarball did not download)"; exit 0; }
  TAR=$W/rel.tar.gz
fi

tar xzf "$TAR" -C "$W/src" || { echo "SKIP: tutrelease (the tarball did not unpack)"; exit 0; }
SRC=$(find "$W/src" -maxdepth 1 -type d -name 'm9-*' | head -1)
[ -n "$SRC" ] && [ -x "$SRC/build.sh" ] ||
  { echo "SKIP: tutrelease (no m9-VERSION/build.sh in the tarball)"; exit 0; }

( cd "$SRC" && OUT="$W/out" ./build.sh >/dev/null 2>&1 ) ||
  { echo "FAIL: the released tarball does not build with cc alone"; exit 1; }
M9C=$W/out/m9c
[ -x "$M9C" ] || { echo "FAIL: the released tarball built no m9c"; exit 1; }
VER=$("$M9C" --version 2>&1 | head -1)

# tutcommon's own recipe, so the gate and the recorder cannot drift --
# but pointed at the RELEASE's library and runtime, because that is
# what the reader's package installs
RT=$SRC/runtime
LIB=$SRC/corpus
. ./tutcommon.sh

# the two that bind C libraries CI does not have; tutdiff skips them
# for the same reason and says so
ZARR_OK=1
ldconfig -p 2>/dev/null | grep -q 'libblosc\.so\.1' || ZARR_OK=0

ran=0; skipped=0
for f in "$EXA"/C*.m9; do
  m=$(basename "$f" .m9)
  if { [ "$m" = C8Zarr ] || [ "$m" = C10Icos ]; } && [ "$ZARR_OK" != 1 ]; then
    skipped=$((skipped+1)); continue
  fi
  tut_build "$m" ||
    { echo "FAIL: $m does not build with $VER, which chapter 0 tells a reader to install"; exit 1; }
  tut_pre "$m"
  ( cd "$EXA" && "$W/$m" > "$W/$m.out" ) ||
    { echo "FAIL: $m exits nonzero under $VER"; exit 1; }
  cmp -s "$W/$m.out" "$EXA/expect/$m.out" ||
    { echo "FAIL: $m answers differently under $VER"; \
      diff "$EXA/expect/$m.out" "$W/$m.out" | head -6; exit 1; }
  ran=$((ran+1))
done

# AND THE REFUSALS, which the chapters QUOTE: a reader who types the
# broken example must see the message the page shows.  This is where
# the exposure actually bites -- the parse and NEW diagnostics both
# changed on 2026-08-30, and a chapter quoting one of them would have
# gone stale for everyone on the released package.
nx=0
for f in "$EXA"/X*.m9; do
  m=$(basename "$f" .m9)
  want=$(sed -n 's/^(\* EXPECT-ERROR: \(.*\) \*)$/\1/p' "$f")
  [ -n "$want" ] || { echo "FAIL: $m has no EXPECT-ERROR line"; exit 1; }
  got=$( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -c "$f" 2>&1 | head -4 )
  case "$got" in
    *"$want"*) nx=$((nx+1)) ;;
    *) echo "FAIL: $m's refusal differs under $VER"
       echo "  the chapter says: $want"
       echo "  $VER says:        $(echo "$got" | head -1)"
       exit 1 ;;
  esac
done

echo "tutrelease: $ran examples and $nx refusals agree with $VER (the released package), $skipped skipped"
