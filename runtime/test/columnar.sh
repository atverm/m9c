#!/bin/sh
# Parquet's and NetCDF's WRITERS against somebody else's readers.
#
# A writer's output is not unique, so there is no golden file to hold
# it to: it is right when a reader that is not this repository's own
# reads back what went in.  The M9 program columnarout writes two
# Parquet files (every Options field asked, and nothing asked) and two
# NetCDF files (a classic grid, a netCDF-4 file of text attributes);
# columnarcheck.py has pyarrow read the first two and netCDF4-python
# -- with libnetcdf's nc_get_att_text for an attribute's octets -- the
# last two.  corpus/ParquetTest.m9 and NetCDFTest.m9 hold the same
# through M9's own readers; this is the outside witness.  Each half
# SKIPS OUT LOUD when its reader is not installed (CI has neither
# pyarrow nor, until the job installs it, python3-netcdf4: build.skips).
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }
# the Python that judges the PARQUET half: $COLUMNAR_PY when the
# system's has no pyarrow (zoefii: ~/miniconda3/bin/python3, pyarrow
# 25.0.1 -- the suite sets it, or that half SKIPs there).  The NETCDF
# half stays on the system python3 and its distribution netCDF4: it
# loads libnetcdf through ctypes, and miniconda's Python loading the
# system's libnetcdf failed on a libssh2 symbol (2026-10-09, suite 30)
PY=${COLUMNAR_PY:-python3}
command -v "$PY" >/dev/null 2>&1 || { echo "SKIP: columnar (no $PY)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: columnar (no python3)"; exit 0; }

OUT=$(mktemp -d /tmp/m9columnar.XXXXXX)
mkdir -p "$OUT/data"
cp columnarout.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"
( cd "$OUT" && "$M9C" --make -o columnarout columnarout.m9 >/dev/null 2>&1 ) \
  || { echo "FAIL: columnarout does not build"; exit 1; }
"$OUT/columnarout" "$OUT/data" || { echo "FAIL: columnarout"; exit 1; }

$PY columnarcheck.py parquet "$OUT/data"
python3 columnarcheck.py netcdf "$OUT/data"
rm -rf "$OUT"
