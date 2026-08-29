#!/bin/sh
# P5 stage-2 differential: the M9-compiled generator against the FPC
# oracle, byte-compared over every corpus module -- including Gen.m9
# generating itself.  The dep lists must match gentest.pas exactly.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/Parse.c ../gen/Gen.c gendump_m9.c -o gendump_m9
( cd ../../host/fpc && fpc -O2 gendump.pas >/dev/null )
n=0
run () {
  m=$1; shift
  ( cd ../../host/fpc && ./gendump "$m" "$@" ) > /tmp/gen_fpc.txt
  ( cd ../../host/fpc && ../../runtime/test/gendump_m9 "$m" "$@" ) \
    > /tmp/gen_m9.txt
  cmp /tmp/gen_fpc.txt /tmp/gen_m9.txt || { echo "DIVERGES: $m"; exit 1; }
  n=$((n+1))
}
run DynStr
run Mat Math
run Stats Math
run Json DynStr
run Http DynStr
run HttpServer DynStr Http
run OpenApi HttpServer DynStr
run ZarrStore DynStr Json Http
run Plot DynStr Mat
run Lex DynStr
run Ast
run Print Ast DynStr
run Parse Ast Lex DynStr
run Dict
run Fmt DynStr
run Io DynStr
run Time DynStr Fmt
run Text DynStr
run Math
run Csv DynStr Io Time
run Frame Csv Io Math DynStr Fmt Time NetCDF
run Parquet Frame Io DynStr Csv Math Fmt Time NetCDF
run NetCDF DynStr
run Grib DynStr
run Syslog DynStr
run Logger DynStr Fmt Io Syslog Time
run Hello Io DynStr
run Concat Io DynStr
run Sem Ast DynStr Fmt Print Text
run Doc Ast DynStr Text Print Lex
run M9c Io Ast Parse Gen Sem DynStr Doc Lex
run Gen Ast DynStr
echo "gendiff: $n modules, generated C byte-identical to the oracle"
