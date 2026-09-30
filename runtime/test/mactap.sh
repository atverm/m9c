#!/bin/sh
# The macOS package, end to end, the way tools/release/mac/m9.rb
# builds it: the tarball a release would cut from HEAD (the public
# list), Homebrew's gcc as CC, build.sh into a DESTDIR whose usr/ is
# the keg, the two gcc-slot scripts -- and then the result used from
# an EMPTY environment, as the formula's test and the receipt use it.
# The winzip gate's idea, for the tap: what the reader installs is
# rebuilt here from the tree and made to work, so a change that
# breaks the recipe is seen before the release does.
#
# NOT `brew install`: that writes into the machine's Homebrew, and a
# gate must not.  The formula's steps are repeated here by hand, and
# the formula itself is held to them: its syntax (ruby -c), and the
# four lines this gate depends on being there.  mactap.sh, the
# release builder, is the one that really installs.
#
# Runs on macOS with Homebrew's gcc and openssl@3; anywhere else it
# says so and SKIPs, as winzip does without wine.
#
# What it proves:
#   1  the formula parses
#   2  the tarball is the public list and holds what the formula
#      needs (build.sh, the bootstrap C, the library)
#   3  build.sh builds and installs the DESTDIR layout with gcc, and
#      says NOTHING but its own three lines -- no warning anywhere,
#      the zip's standard
#   4  from an empty environment the keg's m9c compiles and runs a
#      program, through the gcc slot, with no warning
#   5  a program that makes an Http request links flagless (the
#      runtime archive and OpenSSL are supplied; the 0.11.0 package
#      failed exactly there)
#   6  a program with threads holds a monitor (the macOS monitor is
#      made on first entry; a zeroed pthread mutex is invalid there)
set -u

R=$(cd "$(dirname "$0")/../.." && pwd)
F=$R/tools/release/mac/m9.rb

[ "$(uname -s)" = Darwin ] || { echo "mactap: SKIP -- not macOS"; exit 0; }
BREW=${HOMEBREW_PREFIX:-/opt/homebrew}
[ -d "$BREW/opt/gcc/bin" ] || { echo "mactap: SKIP -- no Homebrew gcc at $BREW/opt/gcc/bin (brew install gcc)"; exit 0; }
[ -f "$BREW/opt/openssl@3/include/openssl/ssl.h" ] || { echo "mactap: SKIP -- no Homebrew openssl@3"; exit 0; }
GCC=$(ls "$BREW"/opt/gcc/bin/gcc-[0-9]* 2>/dev/null | head -1)
[ -x "$GCC" ] || { echo "mactap: SKIP -- no gcc-NN in $BREW/opt/gcc/bin"; exit 0; }

W=$(mktemp -d)
status=1
cleanup () { rc=$status; rm -rf "$W"; exit $rc; }   # a cleanup must not decide the verdict
trap cleanup EXIT INT TERM

fail=0
ok  () { echo "  ok    $1"; }
bad () { echo "  FAIL  $1"; fail=1; }

# --- 1 the formula parses, and names the steps repeated below -------
if ruby -c "$F" >/dev/null 2>&1; then ok "m9.rb parses"; else bad "m9.rb does not parse (ruby -c)"; fi
for want in 'system "./build.sh", buildpath/"stage"' \
            'prefix.install Dir\[buildpath/"stage/usr/\*"\]' \
            'opt/gcc/bin/#{tool}-\[0-9\]\*' \
            'depends_on "openssl@3"'; do
  if grep -q -- "$want" "$F"; then :; else bad "m9.rb no longer says: $want"; fi
done
[ $fail = 0 ] && ok "m9.rb names the recipe this gate repeats"

# --- 2 the tarball, as vroem.sh prepare cuts it -------------------------
VER=$(sh "$R/tools/release/version.sh")
cd "$R"
. tools/release/publiclist.sh
# shellcheck disable=SC2086
git archive --format=tar.gz --prefix="m9-$VER/" -o "$W/m9-$VER.tar.gz" HEAD -- $M9_PUBLIC \
  || { bad "git archive of the public list"; status=1; exit 1; }
( cd "$W" && tar xzf "m9-$VER.tar.gz" )
SRC=$W/m9-$VER
for f in build.sh runtime/gen/M9c.c corpus/Io.m9 runtime/tlsshim.c man/m9c.1; do
  [ -f "$SRC/$f" ] || bad "the tarball lacks $f"
done
[ $fail = 0 ] && ok "the tarball holds build.sh, the bootstrap C, the library and the runtime"

# --- 3 the formula's install, by hand ------------------------------
( cd "$SRC" && CC="$GCC" CPPFLAGS="-I$BREW/opt/openssl@3/include" LDFLAGS="-L$BREW/opt/openssl@3/lib" \
    ./build.sh "$W/stage" > "$W/build.log" 2>&1 ) || { bad "build.sh failed:"; tail -5 "$W/build.log"; }
KEG=$W/stage/usr
[ -x "$KEG/bin/m9c" ] && [ -f "$KEG/lib/libm9rt.a" ] && [ -f "$KEG/lib/m9/Io.m9" ] && [ -f "$KEG/include/m9/m9rt.h" ] \
  && ok "the keg has m9c, libm9rt.a, the library and the header" \
  || bad "the keg is incomplete"
if grep -qi "warning" "$W/build.log"; then bad "build.sh warned:"; grep -i warning "$W/build.log" | head -3
else ok "build.sh said nothing but its own lines"; fi
mkdir -p "$KEG/gcc/bin"
for tool in gcc gcc-ar; do
  {
    echo '#!/bin/sh'
    echo "for g in $BREW/opt/gcc/bin/$tool-[0-9]*; do [ -x \"\$g\" ] && exec \"\$g\" \"\$@\"; done"
    echo 'echo "m9c: no Homebrew gcc found -- brew install gcc" >&2; exit 127'
  } > "$KEG/gcc/bin/$tool"
  chmod 755 "$KEG/gcc/bin/$tool"
done

# --- 4, 5, 6 from an empty environment ---------------------------------
mkdir -p "$W/use"
cat > "$W/use/Answer.m9" <<'M9EOF'
MODULE Answer ;
IMPORT Io ;
BEGIN
  Io.WriteLine ('answer=42')
EXCEPT
| ValueRange : Io.Halt (1)
END Answer.
M9EOF
cp "$R/runtime/test/HttpPing.m9" "$R/runtime/test/thrtest.m9" "$W/use/"
USE=$(cd "$W/use" && env -i HOME="$W/use" PATH="$KEG/bin:/usr/bin:/bin" sh -c '
  m9c --version | grep -q "^m9c " || { echo "m9c --version did not answer"; exit 1; }
  m9c -v --make -o answer Answer.m9 > b1.txt 2>&1 || { echo "Answer did not build:"; cat b1.txt; exit 1; }
  grep -q "/gcc/bin/gcc " b1.txt || { echo "the link did not go through the gcc slot:"; grep "^m9c: " b1.txt | tail -1; exit 1; }
  grep -qi "warning" b1.txt && { echo "Answer warned:"; grep -i warning b1.txt; exit 1; }
  [ "$(./answer)" = "answer=42" ] || { echo "answer is not 42"; exit 1; }
  m9c --make -o ping HttpPing.m9 > b2.txt 2>&1 || { echo "HttpPing did not link flagless:"; tail -3 b2.txt; exit 1; }
  ./ping | grep -q "^linked:" || { echo "HttpPing did not run"; exit 1; }
  m9c --make -o thr thrtest.m9 > b3.txt 2>&1 || { echo "thrtest did not build:"; tail -3 b3.txt; exit 1; }
  [ "$(./thr)" = "n = 8999994" ] || { echo "thrtest answered $(./thr)"; exit 1; }
  echo ok
') && ok "answer=42, an Http program linked flagless, a monitor held -- empty environment, through the gcc slot" \
   || bad "the keg in an empty environment: $USE"

if [ $fail = 0 ]; then
  echo "mactap: the tap's recipe holds on this tree ($VER, $(basename "$GCC"), $(sw_vers -productVersion) $(uname -m))"
  status=0
else
  echo "mactap: FAILED"
  status=1
fi
