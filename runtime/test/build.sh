#!/bin/sh
# Compile generated modules against m9rt and run the driver.
# -Wno-unused-label: every proc carries L_ret whether or not a
# RETURN/raise jumps there; uniformity beats a warning.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
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
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Mat.c ../gen/Math.c \
    mat_driver.c -lm -o mat_test
./mat_test

# Statistics against numpy/scipy: the goldens are CHECKED IN
# (tools/statsgold.py regenerates them by hand), so the gate needs
# no python and cannot regenerate what it compares against.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/Stats.c ../gen/Math.c \
    stats_driver.c -lm -o stats_test
./stats_test

# Frame against polars: sample and goldens are CHECKED IN
# (tools/framegold.py regenerates by hand).  Frame imports NetCDF
# (phase 3), so the gate needs the library and SKIPS OUT LOUD
# without it, like the other format batteries.
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../fmtshim.c ../gen/Frame.c \
      ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c ../gen/Math.c \
      ../gen/Fmt.c ../gen/Time.c ../gen/Text.c ../gen/NetCDF.c \
      frame_driver.c -lnetcdf -lm -o frame_test
  ./frame_test

  # Parquet against pyarrow: samples and goldens CHECKED IN
  # (tools/parquetgold.py); the pyarrow re-read inside the driver
  # skips out loud when python3/pyarrow are absent
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../fmtshim.c ../gen/Parquet.c \
      ../gen/Frame.c ../gen/Csv.c ../gen/DynStr.c ../gen/Io.c \
      ../gen/Math.c ../gen/Fmt.c ../gen/Time.c ../gen/Text.c \
      ../gen/NetCDF.c \
      parquet_driver.c -lnetcdf -lm -o parquet_test
  ./parquet_test
else
  echo "SKIP: frame_driver (no /usr/include/netcdf.h)"
fi

# The CSV reader, on the ICOS FLUXNET file when it is on this
# machine.  Skipped out loud otherwise, like the two below.
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -iquote .. -iquote ../gen ../m9rt.c \
    ../gen/DynStr.c ../gen/Io.c ../gen/Fmt.c ../gen/Time.c ../gen/Csv.c \
    csv_driver.c -lm -o csv_test
./csv_test

# The two format libraries the FLEXPART port needs.  Optional, and
# SKIPPED OUT LOUD when absent: a test that silently disappears on a
# machine without a dependency is a test nobody notices losing.
if [ -f /usr/include/netcdf.h ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/NetCDF.c \
      netcdf_driver.c -lnetcdf -lm -o netcdf_test
  ./netcdf_test
else
  echo "SKIP: netcdf_driver (no /usr/include/netcdf.h)"
fi
ECH=$(ls /usr/include/eccodes.h /usr/include/*/eccodes.h 2>/dev/null | head -1)
if [ -n "$ECH" ]; then
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen -I"$(dirname "$ECH")" ../m9rt.c ../gen/DynStr.c \
      ../gen/Grib.c grib_driver.c -leccodes -lm -o grib_test
  ./grib_test
else
  echo "SKIP: grib_driver (no eccodes.h)"
fi
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Json.c json_driver.c \
    -lm -o json_test
./json_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Http.c \
    http_driver.c -lssl -lcrypto -o http_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Http.c \
    ../gen/HttpServer.c ../gen/OpenApi.c httpserver_driver.c -lssl -lcrypto \
    -o httpserver_test
./httpserver_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Http.c ../gen/ZarrStore.c zarr_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o zarr_test
[ -d /tmp/m9stores/co2.zarr ] || python3 ../../tools/genstore.py /tmp/m9stores
python3 -m http.server 18930 --bind 127.0.0.1 --directory /tmp/m9stores \
    >/dev/null 2>&1 &
ZSRV=$!
trap 'kill $ZSRV 2>/dev/null' EXIT
sleep 1
./zarr_test
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../fmtshim.c ../gen/DynStr.c \
    ../gen/Json.c ../gen/Http.c ../gen/ZarrStore.c ../gen/Mat.c \
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
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Http.c ../gen/ZarrStore.c bench_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o bench_test
./bench_test
kill $ZSRV 2>/dev/null
trap - EXIT
printf 'hello from the shim\nM9' > hello.txt
python3 -m http.server 18923 --bind 127.0.0.1 --directory . >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 1
./http_test
kill $SRV 2>/dev/null
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
via heap" ] || { echo "FAIL: string concatenation"; exit 1; }
echo "PASS (1 check) -- + on strings, into HEAP"
