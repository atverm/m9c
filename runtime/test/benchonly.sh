#!/bin/sh
# bench_test alone, against the store server (debug convenience)
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -I.. -I../gen ../m9rt.c ../tcpshim.c ../gen/DynStr.c ../gen/Json.c \
    ../gen/Http.c ../gen/ZarrStore.c bench_driver.c \
    -l:libblosc.so.1 -lm -o bench_test
python3 -m http.server 18930 --bind 127.0.0.1 --directory /tmp/m9stores \
    >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 1
./bench_test
