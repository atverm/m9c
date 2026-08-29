#!/bin/sh
# Build m9c and the M9 runtime library from a source tree.
#
# This is the whole build.  It is a shell script and not a Makefile
# because there are twenty-odd translation units in a fixed order and
# no incremental case worth expressing: a full build is seconds.
#
#   ./build.sh              build into ./out
#   ./build.sh DESTDIR      also install under DESTDIR (packaging)
#
# The bootstrap question, stated plainly: this builds m9c from the C
# in runtime/gen, which is checked in.  That C was produced by m9c
# itself and reproduces byte for byte (runtime/test/bootstrap.sh), so
# a source tree needs a C compiler and nothing else -- no FPC, no
# previous m9c.  The FPC host tooling in host/fpc is the historical
# bootstrap and the differential oracle; it is not needed to build.
set -e
cd "$(dirname "$0")"

CC=${CC:-cc}
# A packager's flags are HONOURED, all three of them: dpkg-buildpackage
# and rpmbuild export CFLAGS, CPPFLAGS and LDFLAGS (hardening lives in
# CPPFLAGS' -D_FORTIFY_SOURCE and LDFLAGS' -z now), and lintian flagged
# m9c for missing exactly those two because only CFLAGS was read.  The
# C standard is ours and stays outside them.
CFLAGS=${CFLAGS:--O2}
CPPFLAGS=${CPPFLAGS:-}
LDFLAGS=${LDFLAGS:-}
OUT=${OUT:-out}
DESTDIR=$1

WARN="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter"

# the modules m9c itself is made of, in dependency order
COMPILER="DynStr Io Lex Ast Parse Print Text Fmt Sem Gen Doc M9c"

# everything else a program may import: the standard library, shipped
# as source (M9 has no binary module format -- the .m9 IS the
# interface, and a second one could disagree with it)
LIBRARY="DynStr Io Lex Ast Parse Print Text Fmt Sem Gen \
         Json Dict Mat Math Time Logger Syslog Http HttpServer OpenApi Doc \
         NetCDF Grib Csv Stats Frame Parquet \
         Plot ZarrStore"

mkdir -p "$OUT"

echo "building m9c ..."
SRC=""
for m in $COMPILER; do SRC="$SRC runtime/gen/$m.c"; done
# shellcheck disable=SC2086
$CC $CPPFLAGS $CFLAGS $WARN -iquote runtime -iquote runtime/gen \
    runtime/m9rt.c $SRC $LDFLAGS -lm -o "$OUT/m9c"

echo "building libm9rt.a ..."
# shellcheck disable=SC2086
$CC $CPPFLAGS $CFLAGS $WARN -iquote runtime -c runtime/m9rt.c -o "$OUT/m9rt.o"
# shellcheck disable=SC2086
$CC $CPPFLAGS $CFLAGS $WARN -iquote runtime -c runtime/tcpshim.c -o "$OUT/tcpshim.o"
ar rcs "$OUT/libm9rt.a" "$OUT/m9rt.o" "$OUT/tcpshim.o"

echo "built $OUT/m9c ($(wc -c < "$OUT/m9c") bytes) and $OUT/libm9rt.a"

[ -n "$DESTDIR" ] || exit 0

echo "installing into $DESTDIR ..."
install -d "$DESTDIR/usr/bin" "$DESTDIR/usr/lib/m9" \
           "$DESTDIR/usr/include/m9" "$DESTDIR/usr/share/man/man1" \
           "$DESTDIR/usr/share/doc/m9"

install -m 755 "$OUT/m9c"        "$DESTDIR/usr/bin/m9c"
install -m 644 "$OUT/libm9rt.a"  "$DESTDIR/usr/lib/libm9rt.a"
install -m 644 runtime/m9rt.h    "$DESTDIR/usr/include/m9/m9rt.h"

# The standard library, as M9 SOURCE.  m9c searches /usr/lib/m9 last,
# so an installed compiler finds these without anyone setting a
# variable -- an installed compiler that cannot find its own library
# is a compiler nobody installs twice.
for m in $LIBRARY; do
  install -m 644 "corpus/$m.m9" "$DESTDIR/usr/lib/m9/$m.m9"
done

# The generated module reference.  debian/control used to Suggest an
# m9-doc package that nothing built; the reference ships in m9
# itself instead, which is one fewer thing to be wrong about.
install -d "$DESTDIR/usr/share/doc/m9/modules"
for f in docs/modules/*.md; do
  install -m 644 "$f" "$DESTDIR/usr/share/doc/m9/modules/"
done

install -m 644 LICENSE           "$DESTDIR/usr/share/doc/m9/LICENSE"
install -m 644 man/m9c.1         "$DESTDIR/usr/share/man/man1/m9c.1"
install -m 644 docs/M9-report.md "$DESTDIR/usr/share/doc/m9/M9-report.md"
install -m 644 docs/pools.md     "$DESTDIR/usr/share/doc/m9/pools.md"
[ -f docs/bench.md ] && install -m 644 docs/bench.md \
    "$DESTDIR/usr/share/doc/m9/bench.md"
# The VS Code extension: syntax highlighting plus docstring hovers
# and completion (fed by m9c --doc).  Extensions are per-user, so
# the package ships the files and the user links them in once:
#   ln -s /usr/share/m9/vscode-m9 ~/.vscode/extensions/atverm.m9-lang-0.2.0
# (or ~/.vscode-server/extensions for VS Code Remote).  README.deb
# in the directory says the same thing.
install -d "$DESTDIR/usr/share/m9/vscode-m9/syntaxes"
for f in package.json extension.js language-configuration.json; do
  install -m 644 "tools/vscode-m9/$f" "$DESTDIR/usr/share/m9/vscode-m9/$f"
done
install -m 644 tools/vscode-m9/syntaxes/*.json \
    "$DESTDIR/usr/share/m9/vscode-m9/syntaxes/"
printf '%s\n' \
  "To use the M9 VS Code extension from this package:" \
  "  ln -s /usr/share/m9/vscode-m9 ~/.vscode/extensions/atverm.m9-lang-0.2.0" \
  "(use ~/.vscode-server/extensions under VS Code Remote), then reload" \
  "VS Code.  Hovers and completion use /usr/bin/m9c; point" \
  "m9.includePaths at your build directory for cross-module docs." \
  > "$DESTDIR/usr/share/m9/vscode-m9/README.deb"

echo "installed"
