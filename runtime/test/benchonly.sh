#!/bin/sh
# bench_test alone, against the store server (debug convenience)
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
# THE SAME LINK LINE AS build.sh's bench_test, kept in step by hand:
# Http grew Io (cc4c40f, 2026-09-10) and TLS (tlsshim, -lssl -lcrypto)
# and this copy, last touched 2026-08-30, did not follow -- it failed
# with undefined Io_IOError/tls_* for weeks, unnoticed because nothing
# runs it (it is not a gate).
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Io.c ../gen/Http.c ../gen/ZarrStore.c bench_driver.c \
    -l:libblosc.so.1 -lssl -lcrypto -lm -o bench_test
# the stores, by their metadata file (build.sh's guard, same reason)
[ -f /tmp/m9stores/co2.zarr/.zarray ] && [ -f /tmp/m9stores/bench.zarr/.zarray ] \
    && [ -f /tmp/m9stores/time.zarr/.zarray ] \
    || python3 ../../tools/genstore.py /tmp/m9stores
python3 -m http.server 18930 --bind 127.0.0.1 --directory /tmp/m9stores \
    >/dev/null 2>&1 &
SRV=$!
trap 'rc=$?; kill $SRV 2>/dev/null || :; exit $rc' EXIT
sleep 1
./bench_test
