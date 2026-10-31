#!/bin/sh
# This gate tests System.Exec: ONE driver, BOTH platforms.
#
# sysx_driver.c drives sysx_child.c, a program of ours rather than sh,
# cat, dd and sleep.  So the same seventeen checks run natively and,
# cross-compiled, under wine.  The driver was written on 2026-09-06 to
# find the Windows half's bugs, and lived in a scratchpad.  It left a
# note behind ("the twin driver should join runtime/test when the
# MSYS2 gate exists to run it"), and this file discharges it.
#
# Only this gate can see these: MS-CRT argument quoting (a space, a
# quote, a trailing backslash, an empty word), two reader threads and
# a writer thread against three anonymous pipes, an environment block
# merged case-insensitively.  Since 2026-09-07 it also sees the bound.
# A run past its deadline is stopped, keeps what it had written, and
# takes the child's own children with it (a process group on POSIX, a
# job object on Windows).  Neither half of that is reachable from the
# other platform's driver.
#
# The native half always runs; the Windows half says why it did not
# rather than passing quietly.
set -u
cd "$(dirname "$0")"

fail=0
ok  () { echo "  ok    $1"; }
bad () { echo "  FAIL  $1"; fail=1; }

W=$(mktemp -d)
status=1
# A cleanup must not decide the verdict.  And it takes two goes.  The
# wineserver outlives the last program by a few seconds and writes its
# registry back into a directory rm has just emptied, so the first
# `rm -rf' leaves system.reg behind and says "Directory not empty".
# wineserver itself is not on PATH on Debian (it is under
# /usr/lib/<triplet>/wine), so waiting it out is the portable way.
cleanup () {
  rc=$status
  rm -rf "$W" 2>/dev/null
  [ -d "$W" ] && { sleep 5; rm -rf "$W" 2>/dev/null; }
  exit $rc
}
trap cleanup EXIT INT TERM

CC=${CC:-gcc}
XC=${M9WINCC:-x86_64-w64-mingw32-gcc}
FLAGS="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter"
SRC="../m9rt.c ../gen/System.c ../gen/Io.c ../gen/DynStr.c ../gen/Text.c sysx_driver.c"

# --- the native half -------------------------------------------------
# runtime/gen is BUILT here when FPC is about, for the reason gen.sh
# gives.  A gate compiled from a stale gen tests the previous version
# of what is being changed and says PASS.
command -v fpc >/dev/null 2>&1 && . ./lib/gen.sh

$CC $FLAGS -O1 -o "$W/sysx_child" sysx_child.c || { bad "the child would not build"; exit 1; }
# shellcheck disable=SC2086
$CC $FLAGS -iquote .. -iquote ../gen $SRC -lm -lpthread -o "$W/sysx_test" \
  || { bad "the driver would not build"; exit 1; }
if out=$("$W/sysx_test" "$W/sysx_child" 2>&1); then
  ok "native: $out"
else
  echo "$out" | sed 's/^/    /'
  bad "native: the driver reported failures"
fi

# --- the Windows half ------------------------------------------------
if [ "${M9WINE:-0}" != 1 ]; then
  # wine retired as a Windows (2026-10-19).  This half runs on the
  # Windows 11 VM, through tools/release/win/vmgates.sh.  M9WINE=1
  # runs it under wine.
  echo "  SKIP  windows: runs on the Windows 11 VM (tools/release/win/vmgates.sh); M9WINE=1 for wine"
elif ! command -v wine >/dev/null 2>&1; then
  echo "  SKIP  windows: no wine"
elif ! command -v "$XC" >/dev/null 2>&1; then
  echo "  SKIP  windows: no $XC (set \$M9WINCC)"
else
  mkdir -p "$W/win"
  # Build with -O1 and no -flto.  This is the runtime under the
  # microscope, and a cross build here is a check on the code, not on
  # the optimiser.
  $XC $FLAGS -O1 -o "$W/win/sysx_child.exe" sysx_child.c \
    || { bad "the child would not cross-compile"; exit 1; }
  # shellcheck disable=SC2086
  $XC $FLAGS -iquote .. -iquote ../gen $SRC -o "$W/win/sysx_test.exe" \
    || { bad "the driver would not cross-compile"; exit 1; }
  WINEPREFIX=$W/prefix
  WINEDEBUG=-all
  export WINEPREFIX WINEDEBUG
  # Pass a bare name, because CreateProcess searches the current
  # directory for one where execvp does not.  That is itself a stated
  # difference between the two platforms.
  # Do NOT run it through a pipe.  `wine ... | grep` reports grep's
  # status, and so a failed compile was read as rc=0 twice in this
  # project.
  ( cd "$W/win" && timeout 300 wine sysx_test.exe sysx_child.exe ) \
    > "$W/win.log" 2>&1
  rc=$?
  if [ "$rc" = 0 ] && grep -q '^PASS' "$W/win.log"; then
    ok "wine: $(grep '^PASS' "$W/win.log")"
  else
    grep -v '^wine: created' "$W/win.log" | sed 's/^/    /'
    bad "wine: the driver exited $rc"
  fi
fi

[ "$fail" = 0 ] && echo "winsys: System.Exec holds on both platforms" \
                || echo "winsys: FAILED"
status=$fail
exit $fail
