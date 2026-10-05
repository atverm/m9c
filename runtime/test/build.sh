#!/bin/sh
# Compile generated modules against m9rt and run the drivers.
# -Wno-unused-label: every proc carries L_ret whether or not a
# RETURN/raise jumps there; uniformity beats a warning.
#
# EVERY BATTERY RUNS, AND THE SCRIPT ANSWERS HOW MANY FAILED.  It
# used to be one `set -e' list: the first driver that did not compile
# ended it, and every battery after that one silently did not run.
# 2026-10-01: twelve stale Csv calls in frame_driver.c (pool elision's
# hidden pool) had hidden twenty batteries since stage 3, and nothing
# said so until a release was cut.  Errors are values here too: each
# battery is a function run in its own subshell under `set -e', its
# failure is counted and NAMED, and the rest still run.
#
#   runtime/test/build.sh                    every battery
#   M9_SKIPS=FILE runtime/test/build.sh      ... and the SKIP lines the
#                                            run printed must be FILE's
#
# M9_SKIPS is how CI holds the skips: a battery that needs a library
# SKIPS OUT LOUD without it and the script still passes, which is
# right on a laptop and wrong on a machine that is supposed to have
# the library -- there, a netCDF battery that stops running must be a
# red diff, not a line nobody reads.  runtime/test/build.skips is
# CI's list.
case ${M9_SKIPS:-} in ""|/*) ;; *) M9_SKIPS=$(pwd)/$M9_SKIPS ;; esac
cd "$(dirname "$0")"
. ./lib/gen.sh || exit 1   # runtime/gen is BUILT here, not found

W=$(mktemp -d /tmp/m9build.XXXXXX)
ALL=$W/all.log
: > "$ALL"
n=0
fail=0
failed=""
battery () {  # battery NAME: run b_NAME under set -e in a subshell
  n=$((n+1))
  # NOT `if ( ... ); then': a shell ignores -e inside a condition,
  # subshell and function included, and the battery would run on
  # past its first failure exactly as if nothing had been set
  ( set -e; "b_$1" ) > "$W/$1.log" 2>&1
  rc=$?
  cat "$W/$1.log"
  cat "$W/$1.log" >> "$ALL"
  if [ "$rc" != 0 ]; then
    fail=$((fail+1))
    failed="$failed $1"
    echo "FAIL: battery $1 (exit $rc)"
    echo "FAIL: battery $1 (exit $rc)" >> "$ALL"
  fi
}

b_dynstr () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c dynstr_driver.c -o dynstr_test
./dynstr_test
}
b_dict () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Dict.c dict_driver.c -o dict_test
./dict_test
}
b_fmt () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c fmt_driver.c \
    -lm -o fmt_test
./fmt_test
}
b_time () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Time.c time_driver.c -lm -o time_test
./time_test
}
b_text () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Io.c ../gen/Time.c ../gen/Text.c ../gen/Syslog.c ../gen/Logger.c \
    text_driver.c -lm -o text_test
./text_test
}
# the system log, observed through LOG_PERROR: a test cannot read the
# journal, but it can read exactly what syslog() was handed
b_syslog () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Io.c ../gen/Time.c ../gen/Syslog.c ../gen/Logger.c syslog_driver.c \
    -lm -o syslog_test
./syslog_test
}
# libm, wrapped: the values must be libm's bit for bit, and the
# domain errors must RAISE rather than return a NaN that travels
b_math () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Math.c math_driver.c \
    -lm -o math_test
./math_test
}
b_mat () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/Mat.c ../gen/Math.c \
    mat_driver.c -lm -o mat_test
./mat_test
}
# Sort: stable merge sorts against a reference, the F64 NaN refusal,
# the argsort's stability, and By called through a C function of the
# procedure type's own signature -- the ABI of par 2.2.3 proven
b_sort () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Sort.c ../gen/Math.c \
    sort_driver.c -lm -o sort_test
./sort_test
}
# Bits: the 64-bit pattern operations against C's own operators over
# a sweep, and the shift counts C leaves undefined refused BY NAME
b_bits () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Bits.c bits_driver.c \
    -o bits_test
./bits_test
}

# System: the process seen from inside.  The driver is run with a
# known argument line so the three argument views can be checked
# against it, and it runs /bin/echo and sh through Exec and reads
# both streams back.
b_system () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/System.c ../gen/Io.c \
    ../gen/DynStr.c ../gen/Text.c system_driver.c -lm -lpthread -o system_test
./system_test --verbose --out=x.nc a -- -b
}

# Statistics against numpy/scipy: the goldens are CHECKED IN
# (tools/statsgold.py regenerates them by hand), so the gate needs
# no python and cannot regenerate what it compares against.
b_stats () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/Stats.c ../gen/Math.c ../gen/Bits.c \
    ../gen/Sort.c stats_driver.c -lm -o stats_test
./stats_test
}

# Frame against polars: sample and goldens are CHECKED IN
# (tools/framegold.py regenerates by hand).  Frame imports NetCDF
# (phase 3), so the gate needs the library and SKIPS OUT LOUD
# without it, like the other format batteries.
b_frame () {
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c ../gen/Frame.c \
      ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c ../gen/Math.c \
      ../gen/Fmt.c ../gen/Time.c ../gen/Text.c ../gen/NetCDF.c ../gen/Sort.c ../gen/Stats.c ../gen/Bits.c \
      frame_driver.c -lnetcdf -lm -o frame_test
  ./frame_test
else
  echo "SKIP: frame_driver (no /usr/include/netcdf.h)"
fi
}
# Parquet against pyarrow: samples and goldens CHECKED IN
# (tools/parquetgold.py); the pyarrow re-read inside the driver
# skips out loud when python3/pyarrow are absent
b_parquet () {
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c ../gen/Parquet.c \
      ../gen/Frame.c ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c \
      ../gen/Math.c ../gen/Fmt.c ../gen/Time.c ../gen/Text.c \
      ../gen/NetCDF.c ../gen/Sort.c ../gen/Stats.c ../gen/Bits.c \
      parquet_driver.c -lnetcdf -lm -o parquet_test
  ./parquet_test
else
  echo "SKIP: parquet_driver (no /usr/include/netcdf.h)"
fi
}

# Delim: the ROW CURSOR, which is Csv's opposite number -- Csv reads a
# whole file and hands out columns, this walks a 9 GB one in bounded
# memory and hands out views.  The fixtures are written by the driver,
# so this needs nothing on the machine.  The check that matters opens
# a 4 KiB block over a ~180 KiB file so lines straddle reads
# repeatedly; measured separately, 4 M rows cost 1.6 MB of RSS at that
# block and 5.9 MB at 1 MiB, flat in the file size.
# Zip is in THIS link and not in Delim's imports: the driver is where
# the two meet, which is where a dependency between them belongs.  M9
# had no procedure types then, so a source could not be passed as a
# function; Delim takes pushed bytes instead.  (No zlib in the link
# since 2026-10-02: Zip inflates in M9.)
b_delim () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Io.c ../gen/Delim.c ../gen/Zip.c ../gen/Bits.c delim_driver.c \
    -lm -o delim_test
./delim_test
}

# Io: a file read while another process is WRITING it.  ReadFile asks
# the size first and the bytes second, and a size of 0 passed back as
# the cap was the size query again -- so a file created empty and
# filled a moment later answered its new length for a buffer of none,
# an IndexError that killed m9setup two runs in six while it polled
# for the tutorial's port file (2026-09-11).  The driver holds that
# window open on purpose and requires that it was actually entered.
b_io () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    io_driver.c -lpthread -lm -o io_test
./io_test
}

# Zip: a member read as a STREAM, which is what Delim's source
# actually is -- SOCAT ships its 9 GB table inside one.  The fixtures
# come from python's zipfile, so the oracle is a real zip writer; the
# driver skips out loud without python3.  Measured separately, when
# the stream went to zlib: a 224 MB member inflated in 0.21 s at
# 2.4 MB of RSS, against python's own zipfile stream at 0.38 s and
# 12.8 MB, byte counts equal.  Since 2026-10-02 the inflate is Zip's
# own, in M9, and the link names no zlib.
b_zip () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Io.c ../gen/Zip.c ../gen/Bits.c zip_driver.c -lm -o zip_test
./zip_test
}

# The CSV reader, on the ICOS FLUXNET file when it is on this
# machine.  Skipped out loud otherwise, like the two below.
b_csv () {
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -iquote .. -iquote ../gen ../m9rt.c \
    ../gen/DynStr.c ../gen/Io.c ../gen/Fmt.c ../gen/Time.c ../gen/Csv.c \
    csv_driver.c -lm -o csv_test
./csv_test
}

# The two format libraries the port needs.  Optional, and
# SKIPPED OUT LOUD when absent: a test that silently disappears on a
# machine without a dependency is a test nobody notices losing.
b_netcdf () {
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/DynStr.c ../gen/NetCDF.c \
      netcdf_driver.c -lnetcdf -lm -o netcdf_test
  ./netcdf_test
else
  echo "SKIP: netcdf_driver (no /usr/include/netcdf.h)"
fi
}
b_grib () {
ECH=$(ls /usr/include/eccodes.h /usr/include/*/eccodes.h 2>/dev/null | head -1)
if [ -n "$ECH" ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen -I"$(dirname "$ECH")" ../m9rt.c ../gen/Faults.c ../gen/DynStr.c \
      ../gen/Grib.c grib_driver.c -leccodes -lm -o grib_test
  ./grib_test
else
  echo "SKIP: grib_driver (no eccodes.h)"
fi
}
b_json () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Json.c json_driver.c \
    -lm -o json_test
./json_test
}
# ApiSpec: the OpenAPI document a service BUILDS, for one whose routes
# are handlers and so have no table to read back.  OpenApi.Document is
# the derived-from-the-router half and keeps its own battery above;
# this one owns the 3.1 shapes and the JSON escaping that the older
# module explicitly does not do.  DynStr and nothing else -- a service
# describing itself must not have to link a TLS stack to do it.
b_apispec () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/ApiSpec.c \
    apispec_driver.c -lm -o apispec_test
./apispec_test
}
# Arrow IPC: a columnar stream nobody can read is worse than none, so
# the oracle is the library the clients use.  The driver checks the
# framing and the size accounting itself, then has pyarrow read the
# file back when it is installed (skips out loud otherwise).
b_arrow () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/DynStr.c ../gen/Arrow.c \
    arrow_driver.c -lm -o arrow_test
./arrow_test
}
b_httpserver () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Io.c ../gen/Http.c \
    ../gen/HttpServer.c ../gen/OpenApi.c httpserver_driver.c -lssl -lcrypto \
    -o httpserver_test
./httpserver_test
}
# A peer that hangs up must be an ERROR, not a death.  SIGPIPE's
# default action kills the process silently, and the ignore lived
# inside m9_exec -- so any program that never spawned a child ran
# with the default, which is how a cancelled download killed the
# zarr proxy (2026-09-07).  The driver carries its own control: a
# child that restores SIG_DFL must still die of the same write, or
# these checks would pass on a platform that never raises it.
b_sigpipe () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c sigpipe_driver.c \
    -o sigpipe_test
./sigpipe_test
}

# Zarr, the WRITER -- ZarrStore below it is the reader, and the two
# meet at the format rather than in the code.  Json is in the closure
# because the consolidated index is RE-SERIALISED rather than pasted;
# this line missed it on the first try, which is the THIRD time a
# hand-kept link list in this project has missed Json specifically.  The driver checks the
# metadata text and the raw chunk bytes itself (at clevel 0 the chunk
# file IS the buffer), then hands the directory to zarr-python and
# xarray when they are on the machine.  -l:libblosc.so.1 by soname,
# as the reader does: libblosc1 ships the runtime and only the -dev
# package ships the libblosc.so the linker would otherwise want.
b_zarrw () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Json.c ../gen/Math.c ../gen/Zarr.c zarrw_driver.c \
    -l:libblosc.so.1 -lm -o zarrw_test
./zarrw_test
}

# THE STORES the three batteries below read over HTTP.  time.zarr is
# the newest store: a /tmp/m9stores from before it exists has co2 and
# bench and still needs the regeneration.  THE TEST IS THE METADATA
# FILE, NOT THE DIRECTORY: on 2026-09-28 the stores had survived a
# reboot as EMPTY directories (tmpfiles cleaned the files, left the
# dirs), `[ -d ]` was satisfied, and zarr_test opened a co2.zarr with
# no .zarray ("OpenArray co2.zarr / FormatError").  A battery of its
# own, so that a machine without numpy or zarr-python says THAT, once,
# and not three FormatErrors.
b_stores () {
[ -f /tmp/m9stores/co2.zarr/.zarray ] && [ -f /tmp/m9stores/bench.zarr/.zarray ] \
    && [ -f /tmp/m9stores/time.zarr/.zarray ] \
    || python3 ../../tools/genstore.py /tmp/m9stores
[ -f /tmp/m9stores/co2.zarr/.zarray ] && [ -f /tmp/m9stores/bench.zarr/.zarray ] \
    && [ -f /tmp/m9stores/time.zarr/.zarray ] \
    || { echo "FAIL: /tmp/m9stores does not hold the three stores"; exit 1; }
echo "PASS (3 stores) -- co2, bench and time are in /tmp/m9stores"
}
b_zarr () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c zarr_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o zarr_test
./zarr_test
}
# THE THREE cmp LINES COULD NOT FAIL.  They read `cmp a b && echo
# identical' under set -e, and a shell does not apply -e to the left
# side of an and-list: a differing SVG printed "differ" and the
# script went on to exit 0 (measured 2026-10-01 on a two-line
# fixture).  Each is now a refusal by name.
b_plot () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../tcpshim.c ../tlsshim.c ../fmtshim.c ../gen/DynStr.c \
    ../gen/Json.c ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c ../gen/Mat.c \
    ../gen/Math.c ../gen/Fmt.c ../gen/Text.c ../gen/Time.c \
    ../gen/Plot.c plot_driver.c -l:libblosc.so.1 -lssl -lcrypto -lm -o plot_test
mkdir -p /tmp/m9plots
./plot_test
for s in co2_columns co2_field co2_anomaly; do
  cmp "/tmp/m9plots/$s.svg" "../../reference/m2-stack/$s.svg" \
      || { echo "FAIL: $s.svg is not byte-identical to the oracle"; exit 1; }
  echo "$s.svg  byte-identical to the oracle"
done
}

# THE BAR CHARTS, which have no Modula-2 oracle -- bars are new, so
# there is nothing to be byte-identical TO.  The checks are
# structural and arithmetic instead: how many rectangles, that a
# stacked pair's edges meet (to the tolerance the DOCUMENT has, since
# every coordinate is printed %.4g), that an outline bar has a stroke
# and no fill, that a whisker appears for each usable error and no
# others, that a chosen colour replaces the palette, and that a log
# axis ticks the decades and labels them by value.  Shown able to
# fail: dropping the stack base turns the touching-edges check red.
b_bars () {
gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c \
    ../gen/DynStr.c ../gen/Io.c ../gen/Math.c ../gen/Mat.c ../gen/Fmt.c ../gen/Text.c ../gen/Time.c ../gen/Plot.c \
    bar_driver.c -lm -o bar_test
./bar_test || { echo "FAIL: the bar battery"; exit 1; }
}
b_bench () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c bench_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o bench_test
./bench_test
}
# Http's own driver, against python's http.server over this
# directory.  The server is this battery's and dies with it.
b_http () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Io.c ../gen/Http.c \
    http_driver.c -lssl -lcrypto -o http_test
printf 'hello from the shim\nM9' > hello.txt
# 5 MB, past the one-shot reader's old 4 MB ceiling; the driver checks
# every byte against the same formula
python3 -c 'import sys; sys.stdout.buffer.write(bytes((i * 7 + 11) % 251 for i in range(5 * 1024 * 1024)))' > big.bin
python3 -m http.server 18923 --bind 127.0.0.1 --directory . >/dev/null 2>&1 &
SRV=$!
trap 'rc=$?; kill $SRV 2>/dev/null || :; rm -f big.bin; exit $rc' EXIT
sleep 1
./http_test
}
b_hello () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c ../gen/Hello.c \
    -o hello_test
# a PROGRAM, not a library: the body became main () and the exit
# status is the err slot's verdict
[ "$(./hello_test)" = "hello, world
1" ] || { echo "FAIL: hello default"; exit 1; }
[ "$(./hello_test alice bob)" = "hello, alice
hello, bob
2" ] || { echo "FAIL: hello with args"; exit 1; }
echo "PASS (2 checks) -- compiled M9 as an executable"
}
b_concat () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Concat.c -o concat_test
# `+` on strings: composed, chained, returned across a frame, and
# HEAP passed by name as an ordinary pool
[ "$(./concat_test)" = "hello, world!
ababab
6
via heap
a|b|c
276.7" ] || { echo "FAIL: string concatenation"; exit 1; }
echo "PASS (1 check) -- + on strings, across a frame, HEAP by name, a view not grown over"
}

# every integer width traps on overflow (par 2.1): until 2026-09-27
# the narrow ones wrapped silently through the I64 helper
b_narrow () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Narrow.c -o narrow_test
[ "$(./narrow_test)" = "I32 max + 1: raised
I32 min - 1: raised
I16 30000 * 2: raised
I8 127 + 1: raised
I8 -(-128): raised
I32 min DIV -1: raised
U8 0 - 1: raised
U16 65535 + 1: raised
U32 3 - 5: raised
U32 65536 * 65536: raised
U64 0 - 1: raised
U64 2^62 * 4: raised
I32 100 + 200: 300
I16 -5 * 6: -30
U32 5 - 3: 2
U64 2^62 * 3 DIV 3 = 2^62: 4611686018427387904
I32 7 MOD 3: 1" ] || { echo "FAIL: narrow integer arithmetic does not trap"; ./narrow_test; exit 1; }
echo "PASS (17 checks) -- every integer width traps on overflow"
}
# procedure types (par 2.2.3): a value called through a parameter,
# through an OPT variable and an OPT field, VAR and RO inside the
# type, the type's RAISES honoured
b_procuse () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/ProcUse.c -o procuse_test
[ "$(./procuse_test)" = "Pick Up 3 2 -> 2
Pick Down 3 2 -> 3
Pick chosen 7 9 -> 9
Apply Twice 1.5 -> 3
Each AddLen -> 15
ValueRange raised, as Kernel declares" ] || { echo "FAIL: procedure types"; ./procuse_test; exit 1; }
echo "PASS (6 checks) -- procedure types: values, OPT, IS SOME, VAR and RO, RAISES"
}
# constant tables (par 2.2.4): CONST X = [ ... ] of integers, reals,
# strings, characters and booleans -- indexed, measured, lent to an RO
# parameter, shadowed by a parameter, and an index past the end raised.
# The second half is where the table LIVES: the checker forbids every
# write, and const data is what makes a write it missed a fault
# rather than a changed constant.
b_agguse () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/AggUse.c -o agguse_test
[ "$(./agguse_test)" = "5
11
28
15
halves
shadow
5 [alpha]
1 [b]
0 []
5 [gamma]
marks
2
Not Found
?
Not Found / ?
1
503 OK is not made / OK
IndexError" ] || { echo "FAIL: constant tables"; ./agguse_test; exit 1; }
nm agguse_test | grep -q ' [rR] Primes_k$' \
  || { echo "FAIL: the constant table Primes is not in read-only data"; nm agguse_test | grep Primes; exit 1; }
# a table that holds STRINGS holds pointers, which a position-independent
# executable relocates at load: such data is .data.rel.ro, read-only
# once relocated (RELRO), and nm calls it `d' -- so by section here
for k in Names_k Ok_k Statuses_k; do
  objdump -t agguse_test | grep -qE " O \.(rodata|data\.rel\.ro)[[:space:]].* $k\$" \
    || { echo "FAIL: the constant $k is not in read-only data"; objdump -t agguse_test | grep "$k"; exit 1; }
done
echo "PASS (22 checks) -- constant tables: five element types, LEN, lending, shadowing, IndexError, read-only data; record aggregates in a CONST, a table and a statement"
}
# a call that raised answered nothing (par 5): `b := Make (0)' raises
# and b keeps the box Make (3) answered, so the line after the handler
# reads 3 and not NULL.  Until 2026-10-03 it died there.
b_shareuse () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/ShareUse.c -o shareuse_test
[ "$(./shareuse_test)" = "made 3
Empty raised, handled
copied 3
peeked 3" ] || { echo "FAIL: a raising call's answer was stored, or a binder lost to a module variable"; ./shareuse_test; exit 1; }
echo "PASS (4 checks) -- a call that raised answered nothing: the target keeps its value, the SHARED copy comes after the test; a binder shadows a module variable"
}

# Http's URL fetcher, against a local fixture server.  IN THE SUITE
# rather than beside it (threads.sh is run by hand) because it is
# local, it takes seconds, and a gate nobody runs rots -- which is the
# same argument the catbench paragraph below makes.
b_deflate () {
# Zip's compressor and Png's encoder, read back by Python's zlib and
# gzip (and Pillow where it is installed): the witness that is not
# this repository's own inflate
sh ./deflate.sh || { echo "FAIL: deflate"; exit 1; }
}

b_httpget () {
sh ./httpget.sh || { echo "FAIL: httpget"; exit 1; }
}

# catbench is a BENCHMARK, not a driver: nothing ran it, so nothing
# compiled it, and it sat broken from the m9_err -> m9_state rename
# until someone tried to use it.  A checked-in C file that no gate
# compiles rots silently -- the same family as a gate that cannot run.
# Compiled here and NOT run: the answer is a measurement, not a check,
# and it takes seconds.
b_catbench () {
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -iquote .. -iquote ../gen ../m9rt.c catbench.c -lm -o /dev/null \
  || { echo "FAIL: catbench.c does not compile"; exit 1; }
echo "PASS (1 check) -- catbench.c still compiles"
}

for b in dynstr dict fmt time text syslog math mat sort bits system stats \
         frame parquet delim io zip csv netcdf grib json apispec arrow \
         httpserver sigpipe zarrw stores; do
  battery "$b"
done
# one server for the three store readers, started here so that it is
# this script's to stop whatever the batteries do
python3 -m http.server 18930 --bind 127.0.0.1 --directory /tmp/m9stores \
    >/dev/null 2>&1 &
ZSRV=$!
trap 'kill $ZSRV 2>/dev/null; exit 130' INT TERM
sleep 1
for b in zarr plot bars bench; do battery "$b"; done
kill $ZSRV 2>/dev/null
trap - INT TERM
for b in http hello concat narrow procuse agguse shareuse deflate httpget catbench; do battery "$b"; done

# THE SKIPS, held to a list when one is given: sorted, leading blanks
# dropped, compared as text.  A line too many is a battery that
# stopped running on a machine meant to run it; a line too few is the
# list being stale.  Both are red.  A `? ' line in the list is
# optional -- the network decides whether it appears -- and is taken
# out of both sides before they are compared.
if [ -n "${M9_SKIPS:-}" ]; then
  n=$((n+1))
  sed 's/^ *//' "$M9_SKIPS" | grep -v '^#' | grep . > "$W/skips.list" || :
  sed -n 's/^? //p' "$W/skips.list" > "$W/skips.opt"
  grep -v '^? ' "$W/skips.list" | sort > "$W/skips.want" || :
  grep -E '^ *SKIP' "$ALL" | sed 's/^ *//' | grep -vxF -f "$W/skips.opt" | sort > "$W/skips.got" || :
  if diff "$W/skips.want" "$W/skips.got" > "$W/skips.diff"; then
    echo "PASS ($(wc -l < "$W/skips.got" | tr -d ' ') skips) -- exactly the SKIP lines $(basename "$M9_SKIPS") expects"
  else
    fail=$((fail+1))
    failed="$failed skips"
    echo "FAIL: the SKIP lines are not the ones $(basename "$M9_SKIPS") expects (< expected, > this run):"
    cat "$W/skips.diff"
  fi
fi

rm -rf "$W"
if [ "$fail" = 0 ]; then
  echo "build: $n batteries, 0 failed"
  exit 0
fi
echo "build: $n batteries, $fail FAILED:$failed"
exit 1
