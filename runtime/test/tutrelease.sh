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
#
# ON CI A SKIP IS A FAILURE.  The skip is for a laptop on a train; a
# CI run that cannot fetch the release has not tested the tutorial
# against it, and exit 0 says it has.  On 0.13.0's release day the
# download failed twice (curl 35, then 28) and both runs "passed" with
# nothing compiled.  GitHub sets CI=true; under it the four ways of
# not getting a tarball are red, after curl's own retries.
set -e
cd "$(dirname "$0")"
REPO=$(cd ../.. && pwd)
EXA=$REPO/docs/tutorial/examples
[ -d "$EXA" ] || { echo "SKIP: tutrelease (no docs/tutorial in this tree)"; exit 0; }

miss () {  # miss WHY: a skip here, a failure on CI
  if [ "${CI:-}" = true ]; then echo "FAIL: tutrelease ($1) -- on CI that is not a skip"; exit 1; fi
  echo "SKIP: tutrelease ($1)"; exit 0
}

W=/tmp/m9tut-release
rm -rf "$W"; mkdir -p "$W/src"

TAR=${M9RELEASE_TARBALL:-}
if [ -z "$TAR" ]; then
  url=$(curl -sSf --max-time 30 --retry 3 --retry-all-errors \
        https://api.github.com/repos/atverm/m9c/releases/latest 2>/dev/null |
        sed -n 's/.*"browser_download_url": *"\([^"]*m9-[0-9.]*\.tar\.gz\)".*/\1/p' |
        head -1) || url=""
  [ -n "$url" ] || miss "no release tarball reachable"
  curl -sSfL --max-time 120 --retry 3 --retry-all-errors -o "$W/rel.tar.gz" "$url" ||
    miss "the release tarball did not download"
  TAR=$W/rel.tar.gz
fi

tar xzf "$TAR" -C "$W/src" || miss "the tarball did not unpack"
SRC=$(find "$W/src" -maxdepth 1 -type d -name 'm9-*' | head -1)
[ -n "$SRC" ] && [ -x "$SRC/build.sh" ] || miss "no m9-VERSION/build.sh in the tarball"

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
. ./lib/tutcommon.sh

# the two that bind C libraries CI does not have; tutdiff skips them
# for the same reason and says so
ZARR_OK=1
ldconfig -p 2>/dev/null | grep -q 'libblosc\.so\.1' || ZARR_OK=0
# and the one that links libnetcdf explicitly (C7Series survives
# without it only because LTO drops the unreachable NetCDF code)
NETCDF_OK=1
printf 'int main(void){return 0;}' > "$W/nc.c"
gcc "$W/nc.c" -lnetcdf -o "$W/nc" 2>/dev/null || NETCDF_OK=0

# WHAT WAITS FOR A RELEASE IS SAID BY NAME, and only that is excused.
#
# This gate was red BY DESIGN from the day the tutorial used
# something the released compiler lacks until the release that
# carried it -- "the tutorial has outgrown the release; cut one".
# True, and useless as a signal: red for a known reason is red that
# hides the next unknown one, and it kept the whole job red on
# develop for work that was declared, dated and waiting (X13Fall,
# 2026-10-01: a refusal 0.13.0 does not make).
#
# So an example that needs the version this tree is building is
# listed in tutrelease.waits with that version, and its disagreement
# with the released compiler is reported as WAITS, not FAIL -- while
# the released version is older than the one it waits for.  Nothing
# else is excused: an example not on the list fails as before; one
# on the list that AGREES with the release is a stale line and fails;
# one whose version is not this tree's fails; and once that version
# is published the line must go (the release's pointer commit).
#
# ON MAIN NOTHING WAITS.  main is what the mirror publishes and the
# site is built from, and a reader on the released package must not
# be shown a page their compiler contradicts.  GitHub says which
# branch; M9_TUTRELEASE_STRICT=1 says it by hand.
WAITS=${M9_TUTRELEASE_WAITS:-$(pwd)/tutrelease.waits}
TV=$(sed -n '1s/^m9 (\([^)]*\)).*/\1/p' "$REPO/debian/changelog" | sed 's/-[0-9]*$//')
RV=$(printf '%s' "$VER" | sed -n 's/.*m9c \([0-9][0-9.]*\).*/\1/p')
STRICT=0
[ "${GITHUB_REF:-}" = refs/heads/main ] && STRICT=1
[ "${M9_TUTRELEASE_STRICT:-}" = 1 ] && STRICT=1

waits_for () {  # waits_for NAME: the version NAME is listed as waiting for, or nothing
  [ -f "$WAITS" ] || return 0
  sed -n "s/^$1  *\([0-9][0-9.]*\).*/\1/p" "$WAITS" | head -1
}
older () {  # older A B: is version A strictly older than B?
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}
nw=0; waited=""; agreed=" "
disagree () {  # disagree NAME WHAT: excused when NAME waits, the gate's failure otherwise
  v=$(waits_for "$1")
  if [ -n "$v" ] && [ "$STRICT" = 0 ] && [ "$v" = "$TV" ] && older "$RV" "$v"; then
    echo "WAITS: $1 $2 -- it needs $v, which this tree is building; the release is $RV"
    nw=$((nw+1)); waited="$waited $1"
    return 0
  fi
  echo "FAIL: $1 $2"
  if [ -n "$v" ] && [ "$STRICT" = 1 ]; then
    echo "  ($1 is listed as waiting for $v, and on main nothing waits: what is published"
    echo "   must agree with the compiler a reader installs)"
  fi
  return 1
}

ran=0; skipped=0
for f in "$EXA"/C*.m9; do
  m=$(basename "$f" .m9)
  if { [ "$m" = C8Zarr ] || [ "$m" = C10Icos ]; } && [ "$ZARR_OK" != 1 ]; then
    skipped=$((skipped+1)); continue
  fi
  if [ "$m" = C14Flux ] && [ "$NETCDF_OK" != 1 ]; then
    echo "SKIP: C14Flux (libnetcdf is absent)"; skipped=$((skipped+1)); continue
  fi
  if ! tut_build "$m"; then
    disagree "$m" "does not build with $VER, which chapter 0 tells a reader to install" || exit 1
    continue
  fi
  tut_pre "$m"
  if ! ( cd "$EXA" && "$W/$m" > "$W/$m.out" ); then
    disagree "$m" "exits nonzero under $VER" || exit 1
    continue
  fi
  if ! cmp -s "$W/$m.out" "$EXA/expect/$m.out"; then
    diff "$EXA/expect/$m.out" "$W/$m.out" | head -6
    disagree "$m" "answers differently under $VER" || exit 1
    continue
  fi
  agreed="$agreed$m "
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
    *"$want"*) nx=$((nx+1)); agreed="$agreed$m " ;;
    *) echo "  $m: the chapter says: $want"
       echo "  $m: $VER says:        $(echo "$got" | head -1)"
       disagree "$m" "is not refused that way under $VER" || exit 1 ;;
  esac
done

# THE LIST IS HELD TOO: every line names an example that exists, waits
# for the version this tree is building, and really does disagree
# with the release.  A line that outlives its reason is how a waiver
# becomes permanent.
if [ -f "$WAITS" ]; then
  sed 's/#.*//' "$WAITS" | grep . > "$W/waits" || :
  while read -r name v rest; do
    [ -f "$EXA/$name.m9" ] ||
      { echo "FAIL: tutrelease.waits names $name, and there is no examples/$name.m9"; exit 1; }
    if ! older "$RV" "$v"; then
      echo "FAIL: tutrelease.waits says $name waits for $v, and $RV is released -- remove the line"; exit 1
    fi
    [ "$v" = "$TV" ] ||
      { echo "FAIL: tutrelease.waits says $name waits for $v; this tree is building $TV"; exit 1; }
    case "$agreed" in
      *" $name "*) echo "FAIL: tutrelease.waits says $name waits for $v, and it agrees with $VER -- remove the line"; exit 1 ;;
    esac
  done < "$W/waits"
fi

if [ "$nw" -gt 0 ]; then
  echo "tutrelease: $ran examples and $nx refusals agree with $VER (the released package), $skipped skipped;"
  echo "            $nw wait for $TV, by name:$waited"
else
  echo "tutrelease: $ran examples and $nx refusals agree with $VER (the released package), $skipped skipped"
fi
