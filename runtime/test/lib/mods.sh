# The toolchain's module list and how to build and run its generator,
# sourced by lib/gen.sh (which makes runtime/gen with it) and
# bootstrap.sh (which shows the result a fixpoint).  Moved here from
# bootstrap.sh on 2026-10-22, when M9Gen.pas was frozen (Alex) and the
# M9 generator became the one that makes runtime/gen.  The callers are
# in runtime/test and set TG, a directory of their own.

# The compiler's C, for the gates that link an m9c from runtime/gen: read
# from build.sh's COMPILER, which ListDiff's rule 9 holds closed under
# imports, so that a new import into the compiler is one line there.
# Until 2026-10-23 twenty gates spelled the list out, and porting Review
# to DynUtf took an edit in each (docs/utfbuilder-plan.md, step 3).
# Relative to runtime/test, where every gate runs.
COMPILERC=$(sed -n 's/^COMPILER="\(.*\)"/\1/p' ../../build.sh | tr ' ' '\n' | sed '/^$/d; s#^#../gen/#; s#$#.c#' | tr '\n' ' ')
[ -n "$COMPILERC" ] || { echo "lib/mods.sh: no COMPILER line in build.sh" >&2; exit 1; }

MODS="DynStr Faults Mat Stats System Frame Parquet NbCells NbShow Json JsonUtf Chars DynUtf Http HttpServer OpenApi ApiSpec Arrow ZarrStore Zarr Plot Lex Ast Print Parse Dict Fmt Io Time Text Math Bits Sort Seq Check Arrays Numeric Csv Delim Zip Png Pg Sparql Regex Xml Rdf Hash Smtp Rsa Map NetCDF Grib Syslog Logger Hello Concat Narrow ProcUse AggUse ShareUse ExportDef ExportUse Gen Sem Doc Review M9c Diag"
deps_of () {
  case $1 in
    Json)          echo DynStr ;;
    Lex)           echo DynStr Text ;;
    JsonUtf)       echo DynStr Text ;;
    Chars)         echo Bits Faults Text ;;
    Http)          echo DynStr Io ;;
    ApiSpec)       echo DynStr ;;
    Arrow)         echo DynStr Faults ;;
    Zarr)          echo DynStr Json Io Math ;;
    Delim)         echo DynStr Io ;;
    Zip)           echo DynStr Io Bits ;;
    Mat)           echo Math Faults ;;
    Sort)          echo Math ;;
    Seq)           echo Sort Text ;;
    Check)         echo Io Fmt Math Text ;;
    Arrays)        echo Faults Math ;;
    Numeric)       echo Faults Math ;;
    Png)           echo Faults Zip Math DynStr ;;
    Stats)         echo Math Bits Faults Sort ;;
    System)        echo Io DynStr Text ;;
    HttpServer)    echo DynStr Http Io Logger Zip ;;
    OpenApi)       echo HttpServer DynStr ;;
    ZarrStore)     echo DynStr Json Http Io ;;
    Pg)            echo DynStr Fmt Time ;;
    Sparql)        echo DynStr Io Http Json Text ;;
    Rdf)           echo DynStr Fmt Json Text Xml ;;
    Regex)         echo DynStr Text ;;
    Map)           echo DynStr Faults Fmt Math Plot Stats Text ;;
    Xml)           echo DynStr Fmt Text ;;
    Hash)          echo Bits Faults ;;
    Smtp)          echo Time DynStr Fmt Text ;;
    Rsa)           echo Hash Text ;;
    Plot)          echo DynStr Mat Math Faults Fmt Text Time ;;
    Print)         echo Ast DynUtf Text ;;
    Gen)           echo Ast DynUtf Text ;;
    Io)            echo DynStr ;;
    Time)          echo DynStr Fmt ;;
    Text)          echo DynStr ;;
    Csv)           echo DynStr Io Time ;;
    Frame)         echo Csv Io Math DynStr Fmt Time NetCDF Faults Sort Stats Text ;;
    Parquet)       echo Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits ;;
    NbCells)       echo Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits ;;
    NbShow)        echo Frame Io DynStr Fmt Text Time ;;
    NetCDF|Grib)   echo DynStr Faults ;;
    Syslog)        echo DynStr ;;
    Logger)        echo DynStr Fmt Io Syslog Time ;;
    Hello|Concat)  echo Io DynStr ;;
    Narrow|ProcUse|AggUse|ShareUse) echo Io ;;
    ExportDef)     echo Io Fmt ;;
    ExportUse)     echo ExportDef Io Fmt ;;
    M9c)           echo Io Ast Parse Gen Sem DynUtf Doc Review Lex System Text ;;
    Review)        echo Ast DynUtf Text ;;
    Sem)           echo Ast DynUtf Print Text ;;
    Doc)           echo Ast DynUtf Text Print Lex ;;
    Parse)         echo Ast Lex Text ;;
    Diag)          echo DynStr DynUtf Io Lex Text ;;
    *)             echo ;;
  esac
}

CFLAGS="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter"
TOOLC="DynStr DynUtf Lex Ast Parse Text Print Sem Gen"

# build a gendump from one stage's sources
build_stage () {                       # build_stage <srcdir> <out>
  src=$1; out=$2
  objs=""
  for m in $TOOLC; do objs="$objs $src/$m.c"; done
  gcc $CFLAGS -I.. -iquote "$src" ../m9rt.c $objs gendump_m9.c -o "$out"
}

# emit every module with one gendump, splitting h and c
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

