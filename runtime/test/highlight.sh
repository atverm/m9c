#!/bin/sh
# The M9 highlighter for JupyterLab (tools/jupyter/highlight) against the
# FPC lexer, over every corpus and museum file: every token it marks as
# a keyword or a string must be one the lexer's dump (host/fpc/lexdump)
# has at the same line and column, and every keyword and string literal
# the lexer has must be marked.  Keywords come from tools/edit/
# keywords.json, which the edit gate holds to the lexer's own table.
# Needs node; CI's lex job has it.
set -e
cd "$(dirname "$0")"
command -v node >/dev/null || { echo "highlight: no node"; exit 1; }
( cd ../../host/fpc && fpc -O2 lexdump.pas >/dev/null )
KW=../../tools/edit/keywords.json
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9 runfix/Shebang.m9; do
  ../../host/fpc/lexdump "$f" | awk '$2 == $3 && $2 ~ /^[A-Z]+$/ { print $1, $2 } $2 == "StrLit" { print $1, "StrLit" }' \
    > /tmp/hl_lex.txt
  node highlight.mjs "$KW" "$f" > /tmp/hl_mode.txt
  cmp -s /tmp/hl_lex.txt /tmp/hl_mode.txt ||
    { echo "highlight: DIVERGES from the lexer on $f"; diff /tmp/hl_lex.txt /tmp/hl_mode.txt | head -8; exit 1; }
  n=$((n+1))
done
echo "highlight: $n files, every keyword and string where the lexer has one"
