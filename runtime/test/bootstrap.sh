#!/bin/sh
# P5 EXIT: the bootstrap fixpoint.
#
#   stage1 = C emitted by the FPC host generator      (runtime/gen)
#   stage2 = C emitted by the M9 generator that was   (runtime/gen2)
#            compiled from stage1
#   stage3 = C emitted by the M9 generator that was   (runtime/gen3)
#            compiled from stage2
#
# stage2 == stage1 says the M9 toolchain reproduces the host's output;
# stage3 == stage2 says it reproduces its OWN, compiled from its own
# output -- the fixpoint, with the FPC host out of the loop.
set -e
cd "$(dirname "$0")"

MODS="DynStr Mat Stats Frame Parquet Json Http HttpServer OpenApi ZarrStore Plot Lex Ast Print Parse Dict Fmt Io Time Text Math Csv NetCDF Grib Syslog Logger Hello Gen Sem Doc M9c"
deps_of () {
  case $1 in
    Json|Http|Lex) echo DynStr ;;
    Mat|Stats)     echo Math ;;
    HttpServer)    echo DynStr Http ;;
    OpenApi)       echo HttpServer DynStr ;;
    ZarrStore)     echo DynStr Json Http ;;
    Plot)          echo DynStr Mat ;;
    Print|Gen)     echo Ast DynStr ;;
    Io|Fmt)        echo DynStr ;;
    Time)          echo DynStr Fmt ;;
    Text)          echo DynStr ;;
    Csv)           echo DynStr Io Time ;;
    Frame)         echo Csv Io Math DynStr Fmt Time NetCDF ;;
    Parquet)       echo Frame Io DynStr Csv Math Fmt Time NetCDF ;;
    NetCDF|Grib)   echo DynStr ;;
    Syslog)        echo DynStr ;;
    Logger)        echo DynStr Fmt Io Syslog Time ;;
    Hello)         echo Io DynStr ;;
    M9c)           echo Io Ast Parse Gen Sem DynStr Doc Lex ;;
    Sem)           echo Ast DynStr Fmt Print Text ;;
    Doc)           echo Ast DynStr Text Print Lex ;;
    Parse)         echo Ast Lex DynStr ;;
    *)             echo ;;
  esac
}

CFLAGS="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter"
TOOLC="DynStr Lex Ast Parse Gen"

# build a gendump from one stage's sources
build_stage () {                       # build_stage <srcdir> <out>
  src=$1; out=$2
  objs=""
  for m in $TOOLC; do objs="$objs $src/$m.c"; done
  gcc $CFLAGS -I.. -iquote "$src" ../m9rt.c $objs gendump_m9.c -o "$out"
}

# emit every module with one gendump, splitting h and c
emit_all () {                          # emit_all <gendump> <outdir>
  gd=$(pwd)/$1                         # absolute: gendump runs in host/fpc
  mkdir -p "$2"
  for m in $MODS; do
    ( cd ../../host/fpc && "$gd" "$m" $(deps_of "$m") ) > /tmp/m9boot.txt
    awk -v h="$2/$m.h" -v c="$2/$m.c" '
      /^==== M9GEN SPLIT ====$/ { sw = 1; next }
      { if (sw) print > c; else print > h }' /tmp/m9boot.txt
  done
}

cmp_all () {                           # cmp_all <dirA> <dirB>
  for m in $MODS; do
    cmp "$1/$m.h" "$2/$m.h" || { echo "DIVERGES: $m.h"; exit 1; }
    cmp "$1/$m.c" "$2/$m.c" || { echo "DIVERGES: $m.c"; exit 1; }
  done
}

rm -rf ../gen2 ../gen3

# STAGE 1 IS MADE HERE, not found here.  This gate used to consume a
# ../gen left behind by whoever last ran gentest, which makes the
# comparison meaningless in both directions: a stale stage1 reports
# DIVERGES against an intact fixpoint (that is how this was noticed,
# after Grib gained a procedure), and -- the dangerous half -- a
# stale stage1 with a stale stage2 built from it reports a fixpoint
# that no longer exists.  An artifact nobody produced in this run is
# not evidence.
echo "stage1: emitting C with the FPC generator ..."
( cd ../../host/fpc && fpc -O2 gentest.pas >/dev/null && ./gentest >/dev/null )

echo "stage2: compiling the M9 toolchain from stage1 C ..."
build_stage ../gen gendump_s1
emit_all gendump_s1 ../gen2
cmp_all ../gen ../gen2
echo "stage2 == stage1  (all $(echo $MODS | wc -w) modules, .h and .c)"

echo "stage3: compiling the M9 toolchain from stage2 C ..."
build_stage ../gen2 gendump_s2
emit_all gendump_s2 ../gen3
cmp_all ../gen2 ../gen3
echo "stage3 == stage2  (all $(echo $MODS | wc -w) modules, .h and .c)"

echo "BOOTSTRAP FIXPOINT REACHED"
