#!/bin/sh
# The manual page against the program.
#
# A help text that drifts from the behaviour is worse than none, and a
# manual page drifts faster than a help text because nobody reads it
# while developing.  So it is not inspected, it is COMPARED: the set of
# options m9c --help lists and the set the OPTIONS section of m9c.1
# documents must be equal, in both directions.
#
# Only option SPELLINGS are compared -- what a reader looks up and what
# a script types.  Comparing prose would be a diff of two documents
# rather than a check of one claim.
#
# Both sides normalise -Idir to -I: the joined spelling is the same
# option, and a set that distinguished them would report a difference
# that does not exist.
set -e
cd "$(dirname "$0")"
MAN=../../man/m9c.1

# $M9C, else the harness build, else the source-tree build.  A package
# build has only the latter, and a check that only runs where it is
# convenient is a check that stops running.
M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=./m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=../../out/m9c; }
[ -n "$M9C" ] || { echo "mandiff: no m9c (run m9c.sh or build.sh)"; exit 1; }
[ -f "$MAN" ] || { echo "mandiff: no manual page at $MAN"; exit 1; }

# A flag is a dash run that starts a word: preceded by start-of-line, a
# space, or a roff macro dot.  That boundary is what keeps 'by-product'
# and 'cross-module' out of the option set.
flags () {
  grep -Eo '(^|[ .])--?[A-Za-z?][-A-Za-z]*|(^|[ ])--([ ]|$)' |
  sed 's/^[ .]//; s/[ ]*$//' |
  sed 's/^\(-I\)..*/\1/' |
  sort -u
}

 "$M9C" --help | sed -n 's/^  \(-.*\)/\1/p' | sed 's/   .*//' | tr ',' ' ' |
  flags > /tmp/m9c-help-opts.txt

# the OPTIONS section only: the rest of the page mentions cc's flags in
# its examples, and -iquote is not ours to document
sed -n '/^\.SH OPTIONS/,/^\.SH [A-Z]/p' "$MAN" | sed 's/\\-/-/g' |
  flags > /tmp/m9c-man-opts.txt

miss=0
while read -r o; do
  grep -qxF -- "$o" /tmp/m9c-man-opts.txt || {
    echo "mandiff: $o is in --help but not in the manual page"
    miss=$((miss + 1)); }
done < /tmp/m9c-help-opts.txt

while read -r o; do
  grep -qxF -- "$o" /tmp/m9c-help-opts.txt || {
    echo "mandiff: $o is documented but --help does not list it"
    miss=$((miss + 1)); }
done < /tmp/m9c-man-opts.txt

if [ "$miss" -ne 0 ]; then
  echo "--- --help lists ---"; cat /tmp/m9c-help-opts.txt
  echo "--- m9c.1 documents ---"; cat /tmp/m9c-man-opts.txt
  echo "mandiff: $miss discrepancies"
  exit 1
fi
n=$(grep -c . /tmp/m9c-help-opts.txt)

# It must also be a page a formatter accepts, not merely a file with
# the right words in it.
if command -v groff >/dev/null 2>&1; then
  if ! groff -man -Tutf8 -ww -z "$MAN" 2>/tmp/m9c-man-warn.txt; then
    echo "mandiff: groff rejected the page"; cat /tmp/m9c-man-warn.txt; exit 1
  fi
  if [ -s /tmp/m9c-man-warn.txt ]; then
    echo "mandiff: groff warnings"; cat /tmp/m9c-man-warn.txt; exit 1
  fi
  echo "mandiff: $n options, --help and m9c.1 agree, groff clean"
else
  echo "mandiff: $n options, --help and m9c.1 agree (groff absent)"
fi
