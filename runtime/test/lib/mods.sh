# This file holds the toolchain's module list and how to build and run
# its generator.  lib/gen.sh sources it to make runtime/gen, and
# bootstrap.sh sources it to show the result a fixpoint.  It moved here
# from bootstrap.sh on 2026-10-22, when M9Gen.pas was frozen (Alex) and
# the M9 generator became the one that makes runtime/gen.  The callers
# are in runtime/test and set TG, a directory of their own.

# COMPILERC lists the compiler's C, for the gates that link an m9c from
# runtime/gen.  It is read from build.sh's COMPILER, which ListDiff's
# rule 9 holds closed under imports.  So a new import into the compiler
# is one line there.  Until 2026-10-23 twenty gates spelled the list
# out, and porting Review to DynUtf took an edit in each
# (docs/utfbuilder-plan.md, step 3).  The paths are relative to
# runtime/test, where every gate runs.
COMPILERC=$(sed -n 's/^COMPILER="\(.*\)"/\1/p' ../../build.sh | tr ' ' '\n' | sed '/^$/d; s#^#../gen/#; s#$#.c#' | tr '\n' ' ')
[ -n "$COMPILERC" ] || { echo "lib/mods.sh: no COMPILER line in build.sh" >&2; exit 1; }

MODS="DynStr Faults Mat Stats System Frame Parquet NbCells NbShow Json JsonUtf Chars DynUtf Tsk Chan Sup Http HttpServer OpenApi ApiSpec Arrow ZarrStore Zarr Plot Lex M9f Ast Print Parse Dict Fmt Io Time Text Math Bits Sort Seq Check Arrays Numeric Csv Delim Zip Png Pg Sparql Regex Xml Rdf Hash Smtp Rsa Map NetCDF Grib Syslog Logger Hello Concat Narrow ProcUse AggUse ShareUse ExportDef ExportUse Gen Sem Doc Review M9c Diag"
deps_of () {
  case $1 in
    Json)          echo DynStr Text ;;
    Lex)           echo DynStr Text ;;
    M9f)           echo DynStr Lex Text ;;
    JsonUtf)       echo DynStr Text ;;
    Chars)         echo Bits Faults Text ;;
    Tsk)           echo Faults System ;;
    Sup)           echo Faults Time Io Fmt ;;
    Http)          echo DynStr Io Text ;;
    ApiSpec)       echo DynStr Text ;;
    Arrow)         echo DynStr Faults Text ;;
    Zarr)          echo DynStr Json Io Math Text ;;
    Delim)         echo DynStr Io Text ;;
    Zip)           echo DynStr Io Bits Text ;;
    Mat)           echo Math Faults ;;
    Sort)          echo Math Text ;;
    Seq)           echo Sort Text ;;
    Check)         echo Io Fmt Math Text ;;
    Arrays)        echo Faults Math ;;
    Numeric)       echo Faults Math ;;
    Png)           echo Faults Zip Math DynStr Text ;;
    Stats)         echo Math Bits Faults Sort ;;
    System)        echo Io DynStr Text ;;
    HttpServer)    echo DynStr Http Io Logger Zip Text ;;
    OpenApi)       echo HttpServer DynStr Text ;;
    ZarrStore)     echo DynStr Json Http Io Text ;;
    Pg)            echo DynStr Fmt Time Text ;;
    Sparql)        echo DynStr Io Http Json Text ;;
    Rdf)           echo DynStr Fmt Json Text Xml ;;
    Regex)         echo DynStr Text ;;
    Map)           echo DynStr Faults Fmt Math Plot Stats Text ;;
    Xml)           echo DynStr Fmt Text ;;
    Hash)          echo Bits Faults Text ;;
    Smtp)          echo Time DynStr Fmt Text ;;
    Rsa)           echo Hash Text ;;
    Plot)          echo DynStr Mat Math Faults Fmt Text Time ;;
    Print)         echo Ast DynStr Text ;;
    Gen)           echo Ast DynStr Text ;;
    Io)            echo DynStr ;;
    Time)          echo DynStr Fmt Text ;;
    Text)          echo DynStr ;;
    Csv)           echo DynStr Io Time Text ;;
    Frame)         echo Csv Io Math DynStr Fmt Time NetCDF Faults Sort Stats Text ;;
    Parquet)       echo Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits Text ;;
    NbCells)       echo Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits Text ;;
    NbShow)        echo Frame Io DynStr Fmt Text Time ;;
    NetCDF)        echo DynStr Faults Text ;;
    Grib)          echo DynStr Faults ;;
    Ast)           echo Text ;;
    Dict)          echo Text ;;
    Syslog|Chan)   echo ;;
    Logger)        echo DynStr Fmt Io Syslog Time Text ;;
    Hello)         echo Io DynStr ;;
    Concat)        echo Io DynStr Text ;;
    Narrow|ShareUse) echo Io ;;
    ProcUse|AggUse) echo Io Text ;;
    ExportDef)     echo Io Fmt ;;
    ExportUse)     echo ExportDef Io Fmt ;;
    M9c)           echo Io Ast Parse Gen Sem DynStr Doc Review Lex M9f System Text ;;
    Review)        echo Ast DynStr Text ;;
    Sem)           echo Ast DynStr Print Text ;;
    Doc)           echo Ast DynStr Text Print Lex ;;
    Parse)         echo Ast Lex Text ;;
    Diag)          echo DynStr Io Lex Text ;;
    *)             echo ;;
  esac
}

# clang warns by default about two forms the generated C uses on
# purpose (a parenthesised comparison, a FOR variable assigned to
# itself).  build.sh turns them off, after -Wall, and so must every gcc
# line with -Werror here.  On macOS `gcc' is clang unless a real one is
# first on PATH, and the self-installer's bootstrap failed with 20
# errors (2026-10-29, report M3).  The test asks the compiler, not the
# OS: a real gcc on a Mac takes no -Wno-self-assign.
CLANGWARN=""
gcc --version 2>/dev/null | grep -qi clang &&
  CLANGWARN="-Wno-parentheses-equality -Wno-self-assign"
CFLAGS="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter $CLANGWARN"
# DynUtf stays in the list: the first generator gen.sh builds is the
# checked-in C, and before the switch its toolchain used DynUtf.
TOOLC="DynStr DynUtf Lex Ast Parse Text Print Sem Gen"

# build_stage builds a gendump from one stage's sources.
build_stage () {                       # build_stage <srcdir> <out>
  src=$1; out=$2
  objs=""
  for m in $TOOLC; do objs="$objs $src/$m.c"; done
  gcc $CFLAGS -I.. -iquote "$src" ../m9rt.c $objs gendump_m9.c -o "$out"
}

# emit_all emits every module with one gendump, splitting h and c.
emit_all () {                          # emit_all <gendump> <outdir>
  case $1 in /*) gd=$1 ;; *) gd=$(pwd)/$1 ;; esac   # gendump runs in host/fpc
  mkdir -p "$2"
  for m in $MODS; do
    ( cd ../../host/fpc && "$gd" "$m" $(deps_of "$m") ) > "$TG"/m9boot.txt ||
      { echo "emit_all: $m did not generate"; return 1; }
    awk -v h="$2/$m.h" -v c="$2/$m.c" '
      /^==== M9GEN SPLIT ====$/ { sw = 1; next }
      { if (sw) print > c; else print > h }' "$TG"/m9boot.txt
  done
}

cmp_all () {                           # cmp_all <dirA> <dirB>
  for m in $MODS; do
    cmp "$1/$m.h" "$2/$m.h" || { echo "DIVERGES: $m.h"; exit 1; }
    cmp "$1/$m.c" "$2/$m.c" || { echo "DIVERGES: $m.c"; exit 1; }
  done
}

