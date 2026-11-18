#!/bin/sh
# This gate holds `m9c --guide` to what it names (0.28.1).
#
# The guide is the agent's first page, so a stale line in it costs
# every session that reads it.  It may name only what exists:
#   1. every probe on a habit line is a file in probes/ or parseprobes/;
#   2. every option it names is one m9c --help lists;
#   3. run from this tree, every place it prints is a path that exists;
#   4. installed (./build.sh DESTDIR), every place it prints is inside
#      DESTDIR and exists: an installed m9c never sends an agent to
#      the web for a document it carries.
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
ROOT=$(cd ../.. && pwd)
fail=0

# A tree run.  freshm9c builds runtime/test/m9c, whose tree is one level
# above its prefix.
"$M9C" --guide > "$TG/guide.txt"
"$M9C" --help > "$TG/help.txt"

# 1. The probe on each habit line: the last word of a line that starts
#    with two spaces and has a run of spaces before it.
grep -E '^  [^ ].*  +[a-z0-9/-]+$' "$TG/guide.txt" | awk '{print $NF}' > "$TG/probes"
n=$(wc -l < "$TG/probes" | tr -d ' ')
[ "$n" -ge 8 ] || { echo "guide: only $n habit lines found; the format changed"; fail=1; }
while read -r p; do
  case $p in
    parseprobes/*) f="$ROOT/$p.m9" ;;
    *) f="$ROOT/probes/$p.m9" ;;
  esac
  [ -f "$f" ] || { echo "guide: names probe $p, which is not $f"; fail=1; }
done < "$TG/probes"

# 2. Every option it names.
grep -oE -- '--[a-z][a-z-]*' "$TG/guide.txt" | sort -u > "$TG/opts"
while read -r o; do
  grep -qE -- "^ +(-[a-zA-Z], )?$o( |,|$)" "$TG/help.txt" ||
    { echo "guide: names $o, which m9c --help does not list"; fail=1; }
done < "$TG/opts"

# 3. Every place, from the tree.
grep -E '^    /' "$TG/guide.txt" | sed 's/^ *//' > "$TG/places"
[ "$(wc -l < "$TG/places" | tr -d ' ')" -ge 4 ] ||
  { echo "guide: from the tree, fewer than 4 places are local paths"; fail=1; }
while read -r p; do
  [ -e "$p" ] || { echo "guide (tree): $p does not exist"; fail=1; }
done < "$TG/places"

# 4. Installed.  build.sh writes out/, which other gates in a lane may
#    be using, so it runs on a copy of the tracked tree (gcconly's way:
#    one tar reads the names).  The paths are compared physical, as
#    m9c prints them (/private/var on macOS).
mkdir -p "$TG/src" "$TG/dest"
( cd "$ROOT" && git ls-files -z | tar --null -T - -cf - ) | ( cd "$TG/src" && tar -xf - )
D=$(cd "$TG/dest" && pwd -P)
( cd "$TG/src" && ./build.sh "$D" > "$TG/install.log" 2>&1 ) ||
  { echo "guide: ./build.sh DESTDIR failed"; tail -5 "$TG/install.log"; exit 1; }
"$D/usr/bin/m9c" --guide > "$TG/guide-inst.txt"
grep -E '^    (/|https:)' "$TG/guide-inst.txt" | sed 's/^ *//' |
  grep -v '^https://tutorial\.' > "$TG/places-inst"
while read -r p; do
  case $p in
    "$D"/*) [ -e "$p" ] || { echo "guide (installed): $p does not exist"; fail=1; } ;;
    *) echo "guide (installed): $p is outside the install"; fail=1 ;;
  esac
done < "$TG/places-inst"

if [ $fail -ne 0 ]; then echo "guide: FAILED"; exit 1; fi
echo "guide: $n probes, $(wc -l < "$TG/opts" | tr -d ' ') options, $(wc -l < "$TG/places" | tr -d ' ') places in the tree and $(wc -l < "$TG/places-inst" | tr -d ' ') installed, all there"
