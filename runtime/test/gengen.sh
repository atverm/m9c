#!/bin/sh
# Re-record gold/c/: the generated C of gendiff's fixtures that are not
# in runtime/gen (which lib/gen.sh writes itself).  A gate that
# regenerates what it compares against cannot fail, so this one only
# writes; read `git diff runtime/test/gold/c` before committing -- it IS
# the change to the generator's output, as runtime/gen's diff is.
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/Parse.c ../gen/Text.c ../gen/Print.c ../gen/Sem.c ../gen/DynUtf.c ../gen/Gen.c \
    gendump_m9.c -o "$TG/gendump_m9"
mkdir -p gold/c
n=0
# each fixture with gendiff's dependency list for it
grep -E '^run [A-Za-z0-9]+' gendiff.sh | while read -r _ m deps; do
  [ -f ../gen/$m.c ] && continue
  ( cd ../../host/fpc && "$TG/gendump_m9" "$m" $deps ) > "gold/c/$m.txt"
  echo "gengen: gold/c/$m.txt"
done
