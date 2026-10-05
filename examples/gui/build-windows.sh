#!/bin/sh
# Builds ./guimean.exe for Windows (x86-64) from Linux, with MinGW.
#
#   sh build-windows.sh
#
# Needs: m9c (0.15 or later) and its runtime sources (the Debian/Ubuntu
# package has them in /usr/share/m9/runtime); MinGW-w64 C and C++
# compilers of the win32 thread model (Debian/Ubuntu: gcc-mingw-w64-
# x86-64-win32, g++-mingw-w64-x86-64-win32); git, meson and ninja the
# first time, for libui-ng.  wine runs the result on Linux.
#
# m9c checks the program and writes it as C; the C never names a
# platform, so MinGW compiles it for Windows like any C.  libui-ng is
# fetched at the commit build.sh pins and built once for Windows.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
LIBUI_COMMIT=43ba1ef
CC=x86_64-w64-mingw32-gcc
command -v $CC >/dev/null || { echo "build-windows.sh: no $CC"; exit 1; }
command -v m9c >/dev/null || { echo "build-windows.sh: m9c is not on PATH"; exit 1; }
M9HOME=$(cd "$(dirname "$(realpath "$(command -v m9c)")")/.." && pwd)
RT=$M9HOME/share/m9/runtime
[ -f "$RT/m9rt.c" ] || { echo "build-windows.sh: no runtime sources in $RT"; exit 1; }

if [ ! -f libui-ng/build-windows/meson-out/libui.a ]; then
  command -v meson >/dev/null && command -v ninja >/dev/null ||
    { echo "build-windows.sh: libui-ng is built with meson and ninja (pip install meson ninja)"; exit 1; }
  [ -d libui-ng ] || git clone -q https://github.com/libui-ng/libui-ng.git
  ( cd libui-ng && git checkout -q "$LIBUI_COMMIT" &&
    printf '%s\n' '[binaries]' \
      "c = 'x86_64-w64-mingw32-gcc'" "cpp = 'x86_64-w64-mingw32-g++'" \
      "ar = 'x86_64-w64-mingw32-ar'" "strip = 'x86_64-w64-mingw32-strip'" \
      "windres = 'x86_64-w64-mingw32-windres'" '[host_machine]' \
      "system = 'windows'" "cpu_family = 'x86_64'" "cpu = 'x86_64'" \
      "endian = 'little'" > mingw.txt &&
    meson setup build-windows --cross-file mingw.txt --buildtype=release \
          --default-library=static -Dtests=false -Dexamples=false >/dev/null &&
    ninja -C build-windows >/dev/null )
  echo "build-windows.sh: libui-ng built for Windows"
fi

rm -rf build-windows && mkdir -p build-windows
cd build-windows
# the program and its library closure as C.  --make checks the program
# and leaves one NAME.h for each module of the closure -- the list --
# but keeps only the program's own C; --out-dir writes one module's C
# without compiling it.  The host objects --make made are not wanted.
LIBDIR=$M9HOME/lib/m9
m9c --make -c "$HERE/GuiMean.m9" >/dev/null
rm -f ./*.o ./*.c
for h in ./*.h; do
  n=$(basename "$h" .h)
  if [ "$n" = GuiMean ]; then m9c --out-dir . "$HERE/GuiMean.m9"
  else m9c --out-dir . "$LIBDIR/$n.m9"; fi
done
for f in ./*.c; do $CC -O2 -c "$f" -iquote "$RT" -iquote . -o "${f%.c}.o"; done
$CC -O2 -c "$RT/m9rt.c" -iquote "$RT" -o m9rt.o
$CC -O2 -c "$HERE/gui.c" -I "$HERE/libui-ng" -o gui.o
# the manifest Windows reads from an EXECUTABLE's resource 1: common
# controls version 6, without which every widget is drawn unthemed
printf '1 24 "%s"\n' "$HERE/libui-ng/windows/libui.manifest" > manifest.rc
x86_64-w64-mingw32-windres manifest.rc -O coff -o manifest.o
# libui-ng's Windows half is C++: g++ links it, statically, so the .exe
# needs nothing beside it but Windows itself
x86_64-w64-mingw32-g++ -O2 ./*.o "$HERE/libui-ng/build-windows/meson-out/libui.a" \
    -static -mwindows \
    -luser32 -lkernel32 -lgdi32 -lcomctl32 -luxtheme -lmsimg32 -lcomdlg32 \
    -ld2d1 -ldwrite -lole32 -loleaut32 -loleacc -luuid -lwindowscodecs \
    -o "$HERE/guimean.exe"
echo "build-windows.sh: built $HERE/guimean.exe"
