#!/bin/sh
# Builds ./guimean on macOS or Linux.
#
#   sh build.sh
#
# Needs: m9c (0.15 or later) and its gcc; git, meson and ninja the first
# time, to fetch and build libui-ng (`pip install meson ninja`, or
# `uv tool install meson` with ninja beside it); on Linux the GTK 3
# headers (Debian/Ubuntu: libgtk-3-dev; Fedora: gtk3-devel).
#
# libui-ng is fetched at a pinned commit into ./libui-ng and built ONCE as
# a static library; later builds only compile the program.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
LIBUI_COMMIT=43ba1ef           # libui-ng master, 2025-03-15

command -v m9c >/dev/null || { echo "build.sh: m9c is not on PATH"; exit 1; }
# the compiler m9c itself uses: its objects are LTO objects, and the link
# has to be done by the compiler that made them
M9HOME=$(cd "$(dirname "$(realpath "$(command -v m9c)")")/.." && pwd)
if [ -x "$M9HOME/gcc/bin/gcc" ]; then CCBIN=$M9HOME/gcc/bin/gcc; else CCBIN=${CC:-cc}; fi

if [ ! -f libui-ng/build/meson-out/libui.a ]; then
  command -v meson >/dev/null && command -v ninja >/dev/null ||
    { echo "build.sh: libui-ng is built with meson and ninja (pip install meson ninja)"; exit 1; }
  [ -d libui-ng ] || git clone -q https://github.com/libui-ng/libui-ng.git
  ( cd libui-ng && git checkout -q "$LIBUI_COMMIT" &&
    meson setup build --buildtype=release --default-library=static \
          -Dtests=false -Dexamples=false >/dev/null &&
    ninja -C build >/dev/null )
  echo "build.sh: libui-ng built ($(cd libui-ng && git log -1 --format=%h))"
fi

mkdir -p build
cd build
m9c --make -c "$HERE/GuiMean.m9"
"$CCBIN" -O2 -c "$HERE/gui.c" -I "$HERE/libui-ng" -o gui.o
case $(uname -s) in
  Darwin)
    # libui-ng's Cocoa half is Objective-C, built by Apple's clang, and
    # asks clang's runtime for @available: its archive comes along
    CLANGRT=$(clang --print-runtime-dir)/libclang_rt.osx.a
    "$CCBIN" -O2 -flto=auto ./*.o -L"$M9HOME/lib" -lm9rt \
        "$HERE/libui-ng/build/meson-out/libui.a" "$CLANGRT" \
        -framework Foundation -framework AppKit -lm -o "$HERE/guimean" ;;
  *)
    "$CCBIN" -O2 -flto=auto ./*.o -L"$M9HOME/lib" -lm9rt \
        "$HERE/libui-ng/build/meson-out/libui.a" $(pkg-config --libs gtk+-3.0) \
        -lm -o "$HERE/guimean" ;;
esac
echo "build.sh: built $HERE/guimean"
