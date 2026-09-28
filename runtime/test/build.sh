#!/bin/sh
# Compile generated modules against m9rt and run the driver.
# -Wno-unused-label: every proc carries L_ret whether or not a
# RETURN/raise jumps there; uniformity beats a warning.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c dynstr_driver.c -o dynstr_test
./dynstr_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Dict.c dict_driver.c -o dict_test
./dict_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c fmt_driver.c \
    -lm -o fmt_test
./fmt_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Time.c time_driver.c -lm -o time_test
./time_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Io.c ../gen/Time.c ../gen/Text.c ../gen/Syslog.c ../gen/Logger.c \
    text_driver.c -lm -o text_test
./text_test
# the system log, observed through LOG_PERROR: a test cannot read the
# journal, but it can read exactly what syslog() was handed
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Io.c ../gen/Time.c ../gen/Syslog.c ../gen/Logger.c syslog_driver.c \
    -lm -o syslog_test
./syslog_test
# libm, wrapped: the values must be libm's bit for bit, and the
# domain errors must RAISE rather than return a NaN that travels
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Math.c math_driver.c \
    -lm -o math_test
./math_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/Mat.c ../gen/Math.c \
    mat_driver.c -lm -o mat_test
./mat_test
# Sort: stable merge sorts against a reference, the F64 NaN refusal,
# the argsort's stability, and By called through a C function of the
# procedure type's own signature -- the ABI of par 2.2.3 proven
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Sort.c ../gen/Math.c \
    sort_driver.c -lm -o sort_test
./sort_test
# Bits: the 64-bit pattern operations against C's own operators over
# a sweep, and the shift counts C leaves undefined refused BY NAME
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Bits.c bits_driver.c \
    -o bits_test
./bits_test

# System: the process seen from inside.  The driver is run with a
# known argument line so the three argument views can be checked
# against it, and it runs /bin/echo and sh through Exec and reads
# both streams back.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/System.c ../gen/Io.c \
    ../gen/DynStr.c ../gen/Text.c system_driver.c -lm -lpthread -o system_test
./system_test --verbose --out=x.nc a -- -b

# Statistics against numpy/scipy: the goldens are CHECKED IN
# (tools/statsgold.py regenerates them by hand), so the gate needs
# no python and cannot regenerate what it compares against.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/Stats.c ../gen/Math.c ../gen/Bits.c \
    stats_driver.c -lm -o stats_test
./stats_test

# Frame against polars: sample and goldens are CHECKED IN
# (tools/framegold.py regenerates by hand).  Frame imports NetCDF
# (phase 3), so the gate needs the library and SKIPS OUT LOUD
# without it, like the other format batteries.
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c ../gen/Frame.c \
      ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c ../gen/Math.c \
      ../gen/Fmt.c ../gen/Time.c ../gen/Text.c ../gen/NetCDF.c \
      frame_driver.c -lnetcdf -lm -o frame_test
  ./frame_test

  # Parquet against pyarrow: samples and goldens CHECKED IN
  # (tools/parquetgold.py); the pyarrow re-read inside the driver
  # skips out loud when python3/pyarrow are absent
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c ../gen/Parquet.c \
      ../gen/Frame.c ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c \
      ../gen/Math.c ../gen/Fmt.c ../gen/Time.c ../gen/Text.c \
      ../gen/NetCDF.c \
      parquet_driver.c -lnetcdf -lm -o parquet_test
  ./parquet_test
else
  echo "SKIP: frame_driver (no /usr/include/netcdf.h)"
fi

# Delim: the ROW CURSOR, which is Csv's opposite number -- Csv reads a
# whole file and hands out columns, this walks a 9 GB one in bounded
# memory and hands out views.  The fixtures are written by the driver,
# so this needs nothing on the machine.  The check that matters opens
# a 4 KiB block over a ~180 KiB file so lines straddle reads
# repeatedly; measured separately, 4 M rows cost 1.6 MB of RSS at that
# block and 5.9 MB at 1 MiB, flat in the file size.
# Zip is in THIS link and not in Delim's imports: the driver is where
# the two meet, which is where a dependency between them belongs.  M9
# has no procedure types, so a source cannot be passed as a function;
# Delim takes pushed bytes instead, and a program reading a plain CSV
# still links no zlib.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../zshim.c ../gen/DynStr.c \
    ../gen/Io.c ../gen/Delim.c ../gen/Zip.c delim_driver.c \
    -lz -lm -o delim_test
./delim_test

# Io: a file read while another process is WRITING it.  ReadFile asks
# the size first and the bytes second, and a size of 0 passed back as
# the cap was the size query again -- so a file created empty and
# filled a moment later answered its new length for a buffer of none,
# an IndexError that killed m9setup two runs in six while it polled
# for the tutorial's port file (2026-09-11).  The driver holds that
# window open on purpose and requires that it was actually entered.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    io_driver.c -lpthread -lm -o io_test
./io_test

# Zip: a member read as a STREAM, which is what Delim's source
# actually is -- SOCAT ships its 9 GB table inside one.  The fixtures
# come from python's zipfile, so the oracle is a real zip writer; the
# driver skips out loud without python3.  Measured separately: a
# 224 MB member inflates in 0.21 s at 2.4 MB of RSS, against python's
# own zipfile stream at 0.38 s and 12.8 MB, byte counts equal.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../zshim.c ../gen/DynStr.c \
    ../gen/Io.c ../gen/Zip.c zip_driver.c -lz -lm -o zip_test
./zip_test

# The CSV reader, on the ICOS FLUXNET file when it is on this
# machine.  Skipped out loud otherwise, like the two below.
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -iquote .. -iquote ../gen ../m9rt.c \
    ../gen/DynStr.c ../gen/Io.c ../gen/Fmt.c ../gen/Time.c ../gen/Csv.c \
    csv_driver.c -lm -o csv_test
./csv_test

# The two format libraries the port needs.  Optional, and
# SKIPPED OUT LOUD when absent: a test that silently disappears on a
# machine without a dependency is a test nobody notices losing.
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/DynStr.c ../gen/NetCDF.c \
      netcdf_driver.c -lnetcdf -lm -o netcdf_test
  ./netcdf_test
else
  echo "SKIP: netcdf_driver (no /usr/include/netcdf.h)"
fi
ECH=$(ls /usr/include/eccodes.h /usr/include/*/eccodes.h 2>/dev/null | head -1)
if [ -n "$ECH" ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen -I"$(dirname "$ECH")" ../m9rt.c ../gen/Faults.c ../gen/DynStr.c \
      ../gen/Grib.c grib_driver.c -leccodes -lm -o grib_test
  ./grib_test
else
  echo "SKIP: grib_driver (no eccodes.h)"
fi
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Json.c json_driver.c \
    -lm -o json_test
./json_test
# ApiSpec: the OpenAPI document a service BUILDS, for one whose routes
# are handlers and so have no table to read back.  OpenApi.Document is
# the derived-from-the-router half and keeps its own battery above;
# this one owns the 3.1 shapes and the JSON escaping that the older
# module explicitly does not do.  DynStr and nothing else -- a service
# describing itself must not have to link a TLS stack to do it.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/ApiSpec.c \
    apispec_driver.c -lm -o apispec_test
./apispec_test
# Arrow IPC: a columnar stream nobody can read is worse than none, so
# the oracle is the library the clients use.  The driver checks the
# framing and the size accounting itself, then has pyarrow read the
# file back when it is installed (skips out loud otherwise).
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../gen/DynStr.c ../gen/Arrow.c \
    arrow_driver.c -lm -o arrow_test
./arrow_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Io.c ../gen/Http.c \
    http_driver.c -lssl -lcrypto -o http_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Io.c ../gen/Http.c \
    ../gen/HttpServer.c ../gen/OpenApi.c httpserver_driver.c -lssl -lcrypto \
    -o httpserver_test
./httpserver_test
# A peer that hangs up must be an ERROR, not a death.  SIGPIPE's
# default action kills the process silently, and the ignore lived
# inside m9_exec -- so any program that never spawned a child ran
# with the default, which is how a cancelled download killed the
# zarr proxy (2026-09-07).  The driver carries its own control: a
# child that restores SIG_DFL must still die of the same write, or
# these checks would pass on a platform that never raises it.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c sigpipe_driver.c \
    -o sigpipe_test
./sigpipe_test

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
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Json.c ../gen/Math.c ../gen/Zarr.c zarrw_driver.c \
    -l:libblosc.so.1 -lm -o zarrw_test
./zarrw_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c zarr_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o zarr_test
# time.zarr is the newest store: a /tmp/m9stores from before it
# exists has co2 and bench and still needs the regeneration.  THE
# TEST IS THE METADATA FILE, NOT THE DIRECTORY: on 2026-09-28 the
# stores had survived a reboot as EMPTY directories (tmpfiles cleaned
# the files, left the dirs), `[ -d ]` was satisfied, and zarr_test
# opened a co2.zarr with no .zarray ("OpenArray co2.zarr / FormatError").
[ -f /tmp/m9stores/co2.zarr/.zarray ] && [ -f /tmp/m9stores/bench.zarr/.zarray ] \
    && [ -f /tmp/m9stores/time.zarr/.zarray ] \
    || python3 ../../tools/genstore.py /tmp/m9stores
python3 -m http.server 18930 --bind 127.0.0.1 --directory /tmp/m9stores \
    >/dev/null 2>&1 &
ZSRV=$!
trap 'rc=$?; kill $ZSRV 2>/dev/null || :; exit $rc' EXIT
sleep 1
./zarr_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../tcpshim.c ../tlsshim.c ../fmtshim.c ../gen/DynStr.c \
    ../gen/Json.c ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c ../gen/Mat.c \
    ../gen/Math.c \
    ../gen/Plot.c plot_driver.c -l:libblosc.so.1 -lssl -lcrypto -lm -o plot_test
mkdir -p /tmp/m9plots
./plot_test
cmp /tmp/m9plots/co2_columns.svg ../../reference/m2-stack/co2_columns.svg \
    && echo 'co2_columns.svg  byte-identical to the oracle'
cmp /tmp/m9plots/co2_field.svg ../../reference/m2-stack/co2_field.svg \
    && echo 'co2_field.svg    byte-identical to the oracle'
cmp /tmp/m9plots/co2_anomaly.svg ../../reference/m2-stack/co2_anomaly.svg \
    && echo 'co2_anomaly.svg  byte-identical to the oracle'

# THE BAR CHARTS, which have no Modula-2 oracle -- bars are new, so
# there is nothing to be byte-identical TO.  The checks are
# structural and arithmetic instead: how many rectangles, that a
# stacked pair's edges meet (to the tolerance the DOCUMENT has, since
# every coordinate is printed %.4g), that an outline bar has a stroke
# and no fill, that a whisker appears for each usable error and no
# others, that a chosen colour replaces the palette, and that a log
# axis ticks the decades and labels them by value.  Shown able to
# fail: dropping the stack base turns the touching-edges check red.
gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c ../gen/Faults.c ../fmtshim.c \
    ../gen/DynStr.c ../gen/Io.c ../gen/Math.c ../gen/Mat.c ../gen/Plot.c \
    bar_driver.c -lm -o bar_test
./bar_test || { echo "FAIL: the bar battery"; exit 1; }
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c bench_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o bench_test
./bench_test
kill $ZSRV 2>/dev/null
trap - EXIT
printf 'hello from the shim\nM9' > hello.txt
# 5 MB, past the one-shot reader's old 4 MB ceiling; the driver checks
# every byte against the same formula
python3 -c 'import sys; sys.stdout.buffer.write(bytes((i * 7 + 11) % 251 for i in range(5 * 1024 * 1024)))' > big.bin
python3 -m http.server 18923 --bind 127.0.0.1 --directory . >/dev/null 2>&1 &
SRV=$!
trap 'rc=$?; kill $SRV 2>/dev/null || :; rm -f big.bin; exit $rc' EXIT
sleep 1
./http_test
kill $SRV 2>/dev/null
rm -f big.bin
trap - EXIT
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
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Concat.c -o concat_test
# `+` on strings: composed, chained, returned across a frame, and
# HEAP passed by name as an ordinary pool
[ "$(./concat_test)" = "hello, world!
ababab
6
via heap
a|b|c" ] || { echo "FAIL: string concatenation"; exit 1; }
echo "PASS (1 check) -- + on strings, across a frame, and HEAP by name"

# every integer width traps on overflow (par 2.1): until 2026-09-27
# the narrow ones wrapped silently through the I64 helper
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
# procedure types (par 2.2.3): a value called through a parameter,
# through an OPT variable and an OPT field, VAR and RO inside the
# type, the type's RAISES honoured
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

# Http's URL fetcher, against a local fixture server.  IN THE SUITE
# rather than beside it (threads.sh is run by hand) because it is
# local, it takes seconds, and a gate nobody runs rots -- which is the
# same argument the catbench paragraph below makes.
sh ./httpget.sh || { echo "FAIL: httpget"; exit 1; }

# catbench is a BENCHMARK, not a driver: nothing ran it, so nothing
# compiled it, and it sat broken from the m9_err -> m9_state rename
# until someone tried to use it.  A checked-in C file that no gate
# compiles rots silently -- the same family as a gate that cannot run.
# Compiled here and NOT run: the answer is a measurement, not a check,
# and it takes seconds.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -iquote .. -iquote ../gen ../m9rt.c catbench.c -lm -o /dev/null \
  || { echo "FAIL: catbench.c does not compile"; exit 1; }
echo "PASS (1 check) -- catbench.c still compiles"
