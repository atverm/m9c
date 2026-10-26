#!/bin/sh
# Regenerate runtime/gen: the C the M9 generator emits for the M9
# toolchain, which every gate that has an M9 side is BUILT FROM (the FPC
# generator made it until 2026-10-22, when M9Gen.pas was frozen).
#
# This exists because six gates read it and none of them made it,
# while the one that did (gendiff) ran last.  A gate compiled from a
# stale gen tests the previous version of the thing being changed and
# says PASS -- which it did, for an alias change neither semdiff nor
# probediff had actually seen.  An artifact nobody produced in this
# run is not evidence.
#
# Sourced, not executed (`. ./lib/gen.sh`), from inside gates that have
# already cd'd to runtime/test.
# THE DIAGNOSTICS SURVIVE A FAILURE.  Both were >/dev/null, so a
# generator that refused a module exited non-zero into `set -e` and
# every caller died with NO OUTPUT AT ALL -- a zero-length log and a
# status of 1, which reads like the shell being broken.  Cost an hour
# on 2026-09-10, when the refusal was one line naming its own cause.
# ONCE A ROUND, NOT ONCE A GATE (2026-10-22): every gate sourced this and
# regenerated the same C, 4.6 s each, two minutes of a round.  It now
# skips when it can PROVE runtime/gen is what the generator would write:
# the hash of every input -- the corpus, this script, the module list,
# the generator's driver --
# equals the one recorded at the last generation, AND the hash of
# runtime/gen equals what that generation wrote (a hand edit, a deleted
# gen, a partial run all regenerate).  Two gates starting at once queue
# on a lock rather than both writing runtime/gen.
GENKEY=$(cd ../.. && pwd | cksum | cut -d' ' -f1)
GENSTAMP="${TMPDIR:-/tmp}/m9genstamp.$GENKEY"
GENLOCK="${TMPDIR:-/tmp}/m9genlock.$GENKEY"
gen_inputs () { cat ../../corpus/*.m9 ./lib/gen.sh ./lib/mods.sh ./gendump_m9.c | cksum | cut -d' ' -f1; }
gen_output () { ls ../gen 2>/dev/null | cksum | cut -d' ' -f1; cat ../gen/* 2>/dev/null | cksum | cut -d' ' -f1; }
# the lists, before the stamp is read: a gate links $COMPILERC whether or
# not this run regenerates (sourced inside the regeneration only, it was
# empty on every run the stamp skipped, 2026-10-23)
. ./lib/mods.sh
GENWAIT=0
while ! mkdir "$GENLOCK" 2>/dev/null; do
  # a gate killed while generating leaves its lock: five minutes is stale
  GENWAIT=$((GENWAIT+1))
  [ "$GENWAIT" -lt 300 ] || { rmdir "$GENLOCK" 2>/dev/null; GENWAIT=0; }
  sleep 1
done
if [ -f "$GENSTAMP" ] && [ "$(cat "$GENSTAMP")" = "$(gen_inputs) $(gen_output | tr '\n' ' ')" ]; then
  rmdir "$GENLOCK"
else
# THE M9 GENERATOR MAKES IT (Alex, 2026-10-22: M9Gen.pas frozen,
# docs/twin-plan.md).  Built from the runtime/gen there is -- the one
# checked in, or HEAD's when the directory is gone -- and run over every
# module until what it writes is what it was built from: the
# bootstrap's fixpoint, reached in two passes when Gen.m9 changed (the
# old generator writes the new one, which writes itself).  A change
# the generator needs in its OWN source lands a commit before its use.
M9GENST=0
M9GT=$(mktemp -d "${TMPDIR:-/tmp}/m9gen.XXXXXX")   # not a fixed name: gates run at once
M9GENTG=${TG:-}
TG=$M9GT
if [ ! -f ../gen/Gen.c ]; then
  ( cd ../.. && git checkout HEAD -- runtime/gen ) > "$M9GT/log" 2>&1 ||
    { echo "gen.sh: runtime/gen is gone and HEAD's could not be checked out --"; cat "$M9GT/log"; M9GENST=1; }
fi
if [ "$M9GENST" = 0 ]; then
  mkdir -p "$M9GT/cur"
  for m in $MODS; do cp ../gen/$m.h ../gen/$m.c "$M9GT/cur/" 2>/dev/null || :; done
  M9PASS=0
  while :; do
    M9PASS=$((M9PASS+1))
    build_stage "$M9GT/cur" "$M9GT/gd" > "$M9GT/log" 2>&1 ||
      { echo "gen.sh: the generator built from runtime/gen did not compile --"; cat "$M9GT/log"; M9GENST=1; break; }
    rm -rf "$M9GT/next"
    emit_all "$M9GT/gd" "$M9GT/next" > "$M9GT/log" 2>&1 ||
      { echo "gen.sh: the M9 generator failed --"; cat "$M9GT/log"; M9GENST=1; break; }
    if diff -rq "$M9GT/cur" "$M9GT/next" > /dev/null 2>&1; then break; fi
    [ "$M9PASS" -lt 4 ] || { echo "gen.sh: no fixpoint after four passes"; M9GENST=1; break; }
    rm -rf "$M9GT/cur"
    mv "$M9GT/next" "$M9GT/cur"
  done
  if [ "$M9GENST" = 0 ]; then
    for m in $MODS; do
      cmp -s "$M9GT/next/$m.h" ../gen/$m.h || cp "$M9GT/next/$m.h" ../gen/$m.h
      cmp -s "$M9GT/next/$m.c" ../gen/$m.c || cp "$M9GT/next/$m.c" ../gen/$m.c
    done
  fi
fi
TG=$M9GENTG
rm -rf "$M9GT"
if [ "$M9GENST" = 0 ]; then
  echo "$(gen_inputs) $(gen_output | tr '\n' ' ')" > "$GENSTAMP"
else
  rm -f "$GENSTAMP"
fi
rmdir "$GENLOCK"
[ "$M9GENST" = 0 ] || exit 1
fi
