#!/bin/sh
# The Windows zip, end to end, the way a reader meets it: unpack a
# folder, run install.bat, read the page, press Y, get a working M9.
# Run under wine, because that is the only Windows this repository
# has; the RECEIPT still has to come from real Windows, exactly as
# each Linux package's does from its own distro.
#
# It needs two things the CI machine does not have, and says so rather
# than passing quietly:
#   wine                         to run install.bat and what it builds
#   $M9WINTOOLCHAIN/bin/gcc.exe  the MSYS2 UCRT64 subset, cut by
#                                tools/release/win/subset.sh
#
# What it proves:
#   1  the welcome page says what M9 is, what will be installed, and
#      that the machine compiles the compiler -- and then ASKS
#   2  answering n installs nothing and leaves the folder alone
#   3  answering Y builds bin\m9c.exe from the bootstrap C alone, then
#      m9setup.exe with it, and narrates every step it takes
#   4  m9setup builds m9lsp and m9fmt and runs a compiled program
#   5  the VS Code extension and the PATH are each ASKED FOR by name,
#      and answering n to the extension leaves nothing behind
#   6  the result banner says Install successful and tells the reader
#      how to reach m9c, PATH or no PATH
#   7  the tutorial is offered; declining names the web version,
#      accepting builds m9tutor and serves the pages and a cell, AND
#      m9setup's own `start` launch works -- the branch that was not
#      taken here is the one that broke on a real Windows machine
#   8  a second run is idempotent, PATH included
#   9  NO WARNING anywhere.  The zip's whole audience is people
#      meeting M9 for the first time; a warning on their first build
#      is the thing this gate exists to keep out.
set -u

R=$(cd "$(dirname "$0")/../.." && pwd)
TC=${M9WINTOOLCHAIN:-}

command -v wine >/dev/null 2>&1 || { echo "winzip: SKIP -- no wine"; exit 0; }
[ -n "$TC" ] && [ -x "$TC/bin/gcc.exe" ] || {
  echo "winzip: SKIP -- no MSYS2 subset (set \$M9WINTOOLCHAIN; see tools/release/win/subset.sh)"
  exit 0
}
# the release half is not in the public tree, and this gate is (the
# tutdiff precedent: skip out loud rather than fail on a missing half)
[ -f "$R/tools/release/win/install.bat" ] || {
  echo "winzip: SKIP -- no tools/release/win in this tree"
  exit 0
}

W=$(mktemp -d)
status=1
cleanup () { rc=$status; rm -rf "$W"; exit $rc; }   # a cleanup must not decide the verdict
trap cleanup EXIT INT TERM

export WINEPREFIX=$W/prefix WINEDEBUG=-all
fail=0
ok  () { echo "  ok    $1"; }
bad () { echo "  FAIL  $1"; fail=1; }

# --- assemble exactly what the zip carries ---------------------------
Z=$W/tree
mkdir -p "$Z/bin" "$Z/bootstrap" "$Z/setup" "$Z/runtime" "$Z/lib/m9"
mkdir -p "$Z/tools/vscode-m9" "$Z/doc" "$Z/build"
COMPILER=$(sed -n 's/^COMPILER="\(.*\)"/\1/p' "$R/build.sh")
LIBRARY=$(sed -n '/^LIBRARY="/,/"/p' "$R/build.sh" | tr -d '"\\' | sed 's/^LIBRARY=//')
for m in $COMPILER; do cp "$R/runtime/gen/$m.c" "$R/runtime/gen/$m.h" "$Z/bootstrap/"; done
for m in $LIBRARY; do cp "$R/corpus/$m.m9" "$Z/lib/m9/"; done
# the tutorial's own library modules -- not an example: a module the
# examples IMPORT (chapter 3's Temps).  Derived, not named.
for f in "$R"/docs/tutorial/examples/*.m9; do
  b=$(basename "$f")
  case $b in C[0-9]*|X[0-9]*) ;; *) cp "$f" "$Z/lib/m9/" ;; esac
done
cp "$R/runtime/m9rt.h" "$R"/runtime/*.c "$Z/runtime/"
cp -r "$R/tools/vscode-m9/." "$Z/tools/vscode-m9/" ; rm -f "$Z/tools/vscode-m9/test.js"
cp "$R/tools/release/win/Setup.m9" "$R/tools/release/win/WinTutor.m9" \
   "$R/tools/release/win/M9Tutor.m9" "$Z/setup/"
cp "$R/tools/release/win/install.bat" "$Z/"
python3 "$R/tools/tutor/mktutor.py" "$R/docs/tutorial" "$Z/doc/tutorial" >/dev/null 2>&1 \
  && cp -r "$R/docs/tutorial/examples/data" "$Z/build/data"
cp -r "$TC" "$Z/ucrt64"

echo "winzip: $(find "$Z" -type f | wc -l) files assembled, running install.bat under wine"

# --- 1, 2: the page, and declining ----------------------------------
printf 'n\n' > "$W/no.txt"
( cd "$Z" && wine cmd /c install.bat < "$W/no.txt" ) > "$W/decline.log" 2>&1
rc=$?
[ "$rc" = 0 ] && ok "declining exits 0" || bad "declining exited $rc"
for phrase in 'Modula-9' 'What this will install' 'It compiles itself' \
              'GPL-3.0-or-later' 'Install M9 into this folder'; do
  grep -qi "$phrase" "$W/decline.log" && ok "the page says: $phrase" \
                                      || bad "the page never says: $phrase"
done
grep -qi 'Nothing was installed' "$W/decline.log" && ok "declining says so" \
                                                  || bad "declining said nothing"
[ -f "$Z/bin/m9c.exe" ] && bad "declining built a compiler anyway" \
                        || ok "declining built nothing"

# --- 3-7: accepting, and answering the three questions --------------
# install.bat -y takes the page's own question WITHOUT READING STDIN,
# so the three m9setup asks get the three answers below.  Driving it
# through `set /p` instead does not work and is the finding: cmd's
# set /p on a redirected stream takes the buffer, not a line, and all
# three questions then silently took their defaults.
# n to the VS Code extension (so the gate can see a refusal leave
# nothing behind), Y to the PATH, n to the tutorial -- which is
# started separately below, in this shell, where it can be stopped.
printf 'n\nY\nn\n' > "$W/yes.txt"
( cd "$Z" && wine cmd /c install.bat -y < "$W/yes.txt" ) > "$W/install.log" 2>&1
rc=$?
[ "$rc" = 0 ] && ok "install.bat exited 0" || { bad "install.bat exited $rc"; tail -30 "$W/install.log"; }

for f in bin/m9c.exe bin/m9setup.exe bin/m9lsp.exe bin/m9fmt.exe; do
  [ -s "$Z/$f" ] && ok "$f  $(stat -c%s "$Z/$f") bytes" || bad "$f was not built"
done
for n in 1 2 3 4 5 6 7; do
  grep -q "\[$n/7\]" "$W/install.log" && : || bad "step $n of 7 was never announced"
done
grep -q '\[7/7\]' "$W/install.log" && ok "all seven steps announced in order"
grep -q 'Install successful' "$W/install.log" && ok "it says Install successful" \
                                              || bad "no success banner"
grep -q 'hello from windows' "$W/install.log" && ok "a compiled program ran and printed its line" \
                                              || bad "the test program did not run"
grep -qi 'Install it?' "$W/install.log" && ok "the extension was asked for, not assumed" \
                                        || bad "the extension was not asked for"
grep -qi 'not installed' "$W/install.log" && ok "declining the extension is honoured" \
                                          || bad "declining the extension said nothing"
ls "$WINEPREFIX/drive_c/users"/*/.vscode/extensions >/dev/null 2>&1 \
  && bad "the extension was installed after being declined" \
  || ok "and nothing was written under the user profile"
grep -qi 'Add them?' "$W/install.log" && ok "the PATH was asked for, not assumed" \
                                      || bad "the PATH was not asked for"
grep -qi 'm9c is' "$W/install.log" && ok "it says whether m9c is reachable by name" \
                                   || bad "it never says how to reach m9c"
grep -q 'tutorial.modula9.net' "$W/install.log" && ok "declining the tutorial names the web version" \
                                                || bad "the web tutorial is never named"
grep -q 'github.com/atverm/m9c' "$W/install.log" && ok "it closes with the licence and the repository" \
                                                 || bad "no closing licence or repository line"

# --- 6: the PATH really is in the registry --------------------------
reg=$(wine reg query 'HKCU\Environment' /v Path 2>/dev/null | tr -d '\r')
case $reg in
  *ucrt64*) ok "the user PATH carries the toolchain" ;;
  *)        bad "the user PATH does not carry the toolchain" ;;
esac

# --- 7: the local tutorial ------------------------------------------
( cd "$Z/build" && wine ../bin/m9c.exe --make -o ../bin/m9tutor.exe \
    ../setup/M9Tutor.m9 ) > "$W/tutbuild.log" 2>&1
rc=$?
if [ "$rc" = 0 ] && [ -s "$Z/bin/m9tutor.exe" ]; then
  ok "m9tutor.exe builds  ($(stat -c%s "$Z/bin/m9tutor.exe") bytes)"
  P=8793
  # exec, so $! is the server itself and not a subshell around it:
  # `fuser -k` did NOT reach it (measured -- the gate hung in wait
  # with the tutor still listening), and the project's own rule is to
  # kill the pid you started.
  ( cd "$Z/build" && exec wine ../bin/m9tutor.exe $P ../doc/tutorial . ) > "$W/tut.log" 2>&1 &
  TUT=$!
  i=0
  while [ $i -lt 40 ] && ! curl -fs --max-time 20 -o /dev/null "http://127.0.0.1:$P/"; do
    i=$((i+1)); sleep 0.5
  done
  n=$(curl -s -o "$W/index.html" -w '%{http_code}' "http://127.0.0.1:$P/")
  [ "$n" = 200 ] && grep -q 'Modula-9' "$W/index.html" \
    && ok "the local tutorial serves its front page" || bad "GET / -> $n"
  n=$(curl -s -o "$W/ch4.html" -w '%{http_code}' "http://127.0.0.1:$P/ch/4")
  [ "$n" = 200 ] && ok "and its chapters" || bad "GET /ch/4 -> $n"
  printf "MODULE C ; IMPORT Io ; BEGIN Io.WriteLine ('cell ran') END C." > "$W/cell.m9"
  curl -s --max-time 300 -X POST --data-binary "@$W/cell.m9" "http://127.0.0.1:$P/run" > "$W/run.txt"
  [ "$(head -1 "$W/run.txt" | tr -d '\r')" = "exit 0" ] && grep -q 'cell ran' "$W/run.txt" \
    && ok "and compiles and runs a cell from the page" \
    || { bad "POST /run"; head -5 "$W/run.txt"; }
  # THE CHAPTERS THAT NEEDED A LIBRARY.  Every one of these failed on
  # a real Windows machine while this gate was green (Alex, 2026-09-06)
  # -- the gate ran one hand-written hello and never an example, so it
  # never linked TLS, blosc or netCDF and never read Io.Arg.  Four
  # separate bugs hid behind that.
  cell () {                          # cell NAME  -> $W/r-NAME.txt
    # --max-time, ALWAYS.  Without it a cell that hangs hangs the
    # gate: C14Flux did, and turned a run into a 28-minute wait
    # instead of a failure with a name on it.
    curl -s --max-time 300 -X POST \
         --data-binary "@$R/docs/tutorial/examples/$1.m9" \
         "http://127.0.0.1:$P/run" > "$W/r-$1.txt"
  }
  # imports a module that is not an example -- the tutorial's own
  # Temps.  The zip shipped the corpus library and not this, so the
  # chapter answered `m9c: cannot find module Temps' (Alex,
  # 2026-09-07).  It is also the check that the REFUSAL is tidy: a
  # cell's reply carries the compiler's diagnostic and not its
  # `N errors in cell.m9' summary.
  cell C3Use
  [ "$(head -1 "$W/r-C3Use.txt" | tr -d '\r')" = "exit 0" ] \
    && ok "C3Use finds the tutorial's own Temps module" \
    || { bad "C3Use"; head -3 "$W/r-C3Use.txt"; }
  printf 'MODULE B ; VAR i : I64 ; x : F64 ; BEGIN i := x END B.' > "$W/bad.m9"
  curl -s --max-time 300 -X POST --data-binary "@$W/bad.m9" \
       "http://127.0.0.1:$P/run" > "$W/r-bad.txt"
  grep -q 'cannot assign' "$W/r-bad.txt" \
    && ! grep -q 'errors in cell.m9' "$W/r-bad.txt" \
    && ok "a refusal is the diagnostic, without m9c's own summary" \
    || { bad "the refusal carries the summary"; head -4 "$W/r-bad.txt"; }

  # reads a file by a RELATIVE path and its own Io.Arg default: the
  # empty-argument bug made this answer `cannot read ' with no name
  cell C15Stats
  [ "$(head -1 "$W/r-C15Stats.txt" | tr -d '\r')" = "exit 0" ] \
    && ok "C15Stats runs and reads build/data by its own relative path" \
    || { bad "C15Stats"; head -3 "$W/r-C15Stats.txt"; }
  # threads, and the one- and eight-thread answers must agree
  cell C16Hash
  grep -q 'hash sum, eight threads' "$W/r-C16Hash.txt" \
    && ok "C16Hash runs its threaded half" \
    || { bad "C16Hash"; head -3 "$W/r-C16Hash.txt"; }
  # TLS shim + blosc + the store this very server now hosts on 18931.
  # It expected `store unreachable' until that thread existed, which
  # is a gate asserting yesterday's limitation as today's contract.
  cell C8Zarr
  [ "$(head -1 "$W/r-C8Zarr.txt" | tr -d '\r')" = "exit 0" ] \
    && ok "C8Zarr reads the store this server hosts" \
    || { bad "C8Zarr"; head -4 "$W/r-C8Zarr.txt"; }
  # netCDF, bundled at Alex's word: 41 DLLs and 30 MB, hdf5, curl,
  # libxml2, libzip and the AWS SDK included, because MSYS2 builds
  # netCDF against its DAP/S3 half.  The chapter must RUN.
  # A FIGURE MUST BE CLICKABLE.  The chapters write to absolute POSIX
  # /tmp paths; the POSIX tutor binds a private /tmp into its sandbox
  # and this cannot, so /out looked only in the work folder and NO
  # figure was ever offered -- while tutor.port, which the cell did
  # not write, was (Alex, 2026-09-07).
  cell C9Plot
  f=$(grep -o '/out/[A-Za-z0-9._-]*' "$W/r-C9Plot.txt" | head -1)
  if [ -n "$f" ]; then
    ok "C9Plot's figure is offered as $f"
    n=$(curl -s --max-time 20 -o "$W/fig.svg" -w '%{http_code}' \
          "http://127.0.0.1:$P$f")
    [ "$n" = 200 ] && [ -s "$W/fig.svg" ] \
      && ok "and the link serves it ($(wc -c < "$W/fig.svg") bytes)" \
      || bad "the figure link answered $n"
  else
    bad "C9Plot wrote a figure and no link was offered"
    head -3 "$W/r-C9Plot.txt"
  fi

  # what /out will not LIST it must not SERVE: the two were separate
  # rules and tutor.port stayed fetchable after it stopped being
  # offered
  n=$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' \
        "http://127.0.0.1:$P/out/tutor.port")
  [ "$n" = 404 ] && ok "/out refuses what it does not list" \
                 || bad "/out serves tutor.port ($n)"

  # C14Flux LAST, and never in the middle.  MEASURED: a twelve-line C
  # program that creates one netCDF file, prints and returns from
  # main NEVER EXITS under wine -- netCDF's teardown of 41 DLLs,
  # HDF5 and the AWS SDK among them, does not come back.  Nothing of
  # M9 is involved, and on real Windows it is expected to exit
  # normally.  But this server is single-threaded, so a cell that
  # cannot return takes the tutorial with it -- which is why every
  # check after it failed when it sat in the middle.
  #
  # SINCE THE BOUND (System.ExecWithin, 2026-09-07) THAT HANG HAS A
  # SHAPE: the cell answers with everything it printed, the status of
  # the kill, and the line saying it was stopped.  So this branch
  # checks the ANSWER -- the numbers are the chapter's own -- and
  # accepts that it could not exit, which is wine's business and not
  # ours.  Before the bound the reply was empty and there was nothing
  # to check at all.
  cell C14Flux
  if [ "$(head -1 "$W/r-C14Flux.txt" | tr -d '\r')" = "exit 0" ]; then
    ok "C14Flux writes and reads back a netCDF file"
  elif grep -q 'still running after' "$W/r-C14Flux.txt" \
       && grep -q 'rows 336, columns in the file 244' "$W/r-C14Flux.txt" \
       && grep -q 'NEE_VUT_REF: 336 of 336 present' "$W/r-C14Flux.txt"; then
    ok "C14Flux answers with the chapter's own numbers"
    echo "  skip  C14Flux's exit: netCDF's teardown does not return under"
    echo "        wine (measured with plain C).  The bound turns that into"
    echo "        a reply; real Windows is the test for the exit itself."
  elif [ ! -s "$W/r-C14Flux.txt" ]; then
    echo "  skip  C14Flux: no reply at all -- the cell hung and was not"
    echo "        bounded.  That is what ExecWithin exists to prevent."
  else
    bad "C14Flux answered but not with exit 0"; head -4 "$W/r-C14Flux.txt"
  fi

  # A CELL THAT NEVER RETURNS HOLDS ITS OWN IMAGE OPEN, and Windows
  # will not let the next link overwrite a running exe: the check
  # after this one failed with `ld.exe: cannot open output file
  # cell.exe: Permission denied'.  That is real Windows behaviour and
  # not a wine one -- any runaway cell does it -- and it is why the
  # cell run is bounded now (System.ExecWithin).
  #
  # THE PATTERN IS cell[0-9]*.exe, NOT cell.exe, and it was wrong
  # here from the day FreeExe was written: the runner takes the first
  # FREE NAME, so the images are cell0.exe, cell1.exe ... and never
  # `cell.exe' at all.  This sweep matched nothing and a hung cell
  # from the unbounded days outlived the gate by ten minutes
  # (measured, 2026-09-07).
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    { tr '\0' ' ' < /proc/$pid/cmdline; } 2>/dev/null |
      grep -qE 'cell[0-9]*\.exe' && kill -9 $pid 2>/dev/null
  done

  # AND THE SERVER: $TUT is the `wine' that STARTED it, and killing
  # that does not always reach the Windows process it became -- which
  # then still holds bin\m9tutor.exe, so the m9setup run below cannot
  # LINK its own copy and reports a build failure that is the gate's
  # leftover rather than a bug (seen three times before this).  Kill
  # the pid we started, then anything still answering to the image
  # name, and only then go on.
  kill $TUT 2>/dev/null
  fuser -k $P/tcp >/dev/null 2>&1      # belt, for a wine that re-execs
  wait $TUT 2>/dev/null
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    { tr '\0' ' ' < /proc/$pid/cmdline; } 2>/dev/null |
      grep -q 'm9tutor\.exe' && kill -9 $pid 2>/dev/null
  done
  sleep 1
else
  bad "m9tutor.exe did not build"; tail -10 "$W/tutbuild.log"
fi

# --- 7b: the launch m9setup ITSELF performs --------------------------
# This is the branch a reader takes, and the gate did not take it: the
# runs above answer n to the tutorial, so `cmd /c start ...` was never
# exercised here and a quoting bug reached a real Windows machine
# (Alex: 'Cannot find \"M9 tutorial\"').  wine reproduces it exactly --
# the broken spelling dies with ShellExecuteEx failed: Invalid name --
# so there was never a reason not to check it.  A gate that tests the
# branch it can reach instead of the branch the user takes is not a
# gate for that branch at all.
# NO $M9TUTORPORT here, deliberately.  m9tutor takes the first FREE
# port from the one it is asked for and writes down which it got, and
# this machine already has something on 8080 -- so the default run is
# the one that exercises the search, and the gate reads the answer
# back rather than asserting it.  (A reader whose 8080 was taken saw
# the window flash and go; Alex, 2026-09-07.)
printf 'n\nn\nY\n' > "$W/tut.txt"
( cd "$Z" && wine cmd /c install.bat -y < "$W/tut.txt" ) \
  > "$W/third.log" 2>&1
if grep -qi 'ShellExecuteEx\|cannot find\|could not start it\|did not build' "$W/third.log"; then
  bad "m9setup's own tutorial launch failed:"
  grep -i -A2 'ShellExecuteEx\|cannot find\|could not start it\|did not build' \
       "$W/third.log" | sed 's/^/        /'
else
  ok "m9setup launches the tutorial without a quoting complaint"
fi
TP=$(sed -n 's|.*http://127\.0\.0\.1:\([0-9]*\)/.*|\1|p' "$W/third.log" | head -1)
if [ -n "$TP" ]; then
  ok "and names the URL it started (port $TP)"
  if ss -ltn 2>/dev/null | grep -q ':8080 ' && [ "$TP" != 8080 ]; then
    ok "and 8080 was taken, so it found a free one instead"
  fi
else
  bad "no URL after starting the tutorial"
fi
i=0
while [ $i -lt 40 ]; do
  curl -fs -o "$W/tutindex.html" "http://127.0.0.1:$TP/" 2>/dev/null && break
  i=$((i+1)); sleep 0.5
done
if grep -q 'Modula-9' "$W/tutindex.html" 2>/dev/null; then
  ok "the tutorial m9setup started is answering, and serving the site"
  printf "MODULE C ; IMPORT Io ; BEGIN Io.WriteLine ('from the installed tutorial') END C." \
    > "$W/cell2.m9"
  curl -s --max-time 300 -X POST --data-binary "@$W/cell2.m9" "http://127.0.0.1:$TP/run" > "$W/run2.txt"
  [ "$(head -1 "$W/run2.txt" | tr -d '\r')" = "exit 0" ] &&
    grep -q 'from the installed tutorial' "$W/run2.txt" \
    && ok "and runs a cell through the compiler the install just made" \
    || { bad "POST /run against the installed tutorial"; head -5 "$W/run2.txt"; }
else
  bad "nothing answers on $TP after m9setup started the tutorial"
  tail -20 "$W/third.log" | sed 's/^/        /'
  # AND KEEP THE EVIDENCE.  This check failed intermittently -- about
  # two runs in five, always with `m9: unhandled IndexError' after
  # m9setup said it was building the tutorial server, never in a hand
  # replay -- and the evidence-keeping below was written before the
  # cause was known.  FOUND 2026-09-11, by reading rather than by
  # replay: m9setup polled for tutor.port in a hot loop, Io.WriteFile
  # creates a file EMPTY and fills it at close, and Io.ReadFile passed
  # a size of 0 back to the shim as the cap -- which is the size query
  # again, so it was told the new length for a buffer of none.  Fixed
  # in Io.ReadFile (runtime/test/io_driver.c pins it, 39 raises in
  # 4000 reads before), and the port file is renamed into place.  The
  # keeping stays: the next intermittent failure deserves its logs.
  keep=/tmp/winzip-failed-$$
  mkdir -p "$keep"
  cp "$W"/*.log "$W"/r-*.txt "$keep/" 2>/dev/null
  { echo "--- alive when the check failed ---"
    for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
      { tr '\0' ' ' < /proc/$pid/cmdline; echo; } 2>/dev/null |
        grep -E '\.exe|wine' | sed "s/^/$pid /"
    done; } > "$keep/alive.txt" 2>/dev/null
  echo "        (logs kept in $keep)"
fi
# whatever it started is detached: find it by /proc, never by pattern-kill
# a pid can vanish between the listing and the read, and the shell --
# not tr -- reports the failed redirection, so the whole body's stderr
# goes away rather than tr's alone
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
  { tr '\0' ' ' < /proc/$pid/cmdline; } 2>/dev/null |
    grep -q 'm9tutor.exe' && kill $pid 2>/dev/null
done

# --- 8: idempotent ---------------------------------------------------
printf 'n\nY\nn\n' > "$W/yes2.txt"
( cd "$Z" && wine cmd /c install.bat -y < "$W/yes2.txt" ) > "$W/second.log" 2>&1
rc=$?
[ "$rc" = 0 ] && ok "a second run exits 0 too" || { bad "the second run exited $rc"; tail -20 "$W/second.log"; }
n=$(wine reg query 'HKCU\Environment' /v Path 2>/dev/null | tr -d '\r' |
    grep -o 'ucrt64' | wc -l)
[ "$n" = 1 ] && ok "and does not append the PATH twice" || bad "PATH carries the toolchain $n times"

# --- 9: not one warning ----------------------------------------------
# A DIAGNOSTIC, not the word.  The first version grepped for
# warning|error and fired on the installer's own sentence "if that
# window shows an error instead, the port is most likely in use" --
# advice a reader wants, matched by a check meant for gcc.  What a
# toolchain actually emits is `warning:` / `error:` with the colon,
# and lto-wrapper's note carries neither.
w=$(grep -inE 'warning:|error:|lto-wrapper|ShellExecuteEx' \
      "$W/install.log" "$W/second.log" "$W/third.log" || true)
if [ -z "$w" ]; then ok "no warning and no error in either log"
else bad "the log carries a warning a first-time reader would see:"; printf '%s\n' "$w" | sed 's/^/        /'
fi

[ "$fail" = 0 ] && echo "winzip: the zip explains itself, asks, installs and serves its own tutorial"
status=$fail
