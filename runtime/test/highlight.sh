#!/bin/sh
# This gate holds the M9 highlighter for JupyterLab
# (tools/jupyter/highlight) against the M9 lexer, over every corpus and
# museum file.  Every token it marks as a keyword or a string must be
# one the lexer's dump (lexdump_m9) has at the same line and column.
# The dump was the Pascal lexer's until 2026-11-15
# (docs/fpc-removal-plan.md, step 3).  Every keyword and string literal the lexer has must be
# marked.  Keywords come from tools/edit/ keywords.json, which the edit
# gate holds to the lexer's own table.  The gate needs node; CI's lex
# job has it.
# Scratch files go in a directory of this run's own.  Fixed /tmp names
# collided between two checkouts or two gates run at once (the compiler
# review's tier 3, 2026-10-22).
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
command -v node >/dev/null || { echo "highlight: no node"; exit 1; }
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c lexdump_m9.c \
    -o "$TG/lexdump"
KW=../../tools/edit/keywords.json
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9 runfix/Shebang.m9; do
  "$TG/lexdump" "$f" | awk '$2 == $3 && $2 ~ /^[A-Z]+$/ { print $1, $2 } $2 == "StrLit" || $2 == "InterpLit" { print $1, "StrLit" }' \
    > "$TG"/hl_lex.txt
  node highlight.mjs "$KW" "$f" > "$TG"/hl_mode.txt
  cmp -s "$TG"/hl_lex.txt "$TG"/hl_mode.txt ||
    { echo "highlight: DIVERGES from the lexer on $f"; diff "$TG"/hl_lex.txt "$TG"/hl_mode.txt | head -8; exit 1; }
  n=$((n+1))
done
echo "highlight: $n files, every keyword and string where the lexer has one"
