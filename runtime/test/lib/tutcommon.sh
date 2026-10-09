# tutcommon: shared by tutgen.sh and tutdiff.sh -- SOURCED, not run,
# which is why it has no execute bit and lives in lib/ (the gen.sh
# precedent; a sourced file in the gate glob read as exit 126).  One
# definition of how each tutorial example is built and run, so the
# recorder and the gate cannot drift.
#
# Expects: M9C EXA RT LIB W set by the caller.

# m9c --make converges by repetition when a DEEP closure builds from
# an empty directory (the documented reverse-pre-order defect in
# MakeAll); one retry is its documented workaround, and the real fix
# is on the compiler's owed list.
tut_make () {
  M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make "$@" >/dev/null 2>&1 || \
  M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make "$@" >/dev/null
}

tut_build () {                  # tut_build MODULE -> $W/MODULE
  # every example links FLAGLESS since 2026-10-09: the FOR "C" units
  # name their libraries (ZarrStore blosc, NetCDF netcdf, Grib
  # eccodes, Pg libpq + pgshim.c) and the runtime carries its shims,
  # so the five hand link lines that stood here -- and that listdiff
  # rule 11 held closed under imports -- are gone; rule 11 now holds
  # that none comes back
  m=$1
  ( cd "$W" && tut_make -o "$m" "$EXA/$m.m9" -I "$EXA" ) || return 1
}

TUT_SRV=
tut_serve () {                  # the zarr chapters' local stores
  [ -n "$TUT_SRV" ] && return 0
  mkdir -p /tmp/m9stores
  # the metadata file, not the directory: an EMPTY store directory
  # (what a reboot's tmpfiles cleaning leaves, 2026-09-28) satisfied
  # `[ -d ]`, and a `cp -r` into it would nest the store one level
  # down -- so the stale directory goes before the copy
  [ -f /tmp/m9stores/co2.zarr/.zarray ] || {
    rm -rf /tmp/m9stores/co2.zarr
    cp -r "$EXA/data/co2.zarr" /tmp/m9stores/; }
  [ -f /tmp/m9stores/icos-obspack.zarr/.zgroup ] || {
    rm -rf /tmp/m9stores/icos-obspack.zarr
    cp -r "$EXA/data/icos-obspack.zarr" /tmp/m9stores/; }
  python3 -m http.server 18931 --bind 127.0.0.1 \
      --directory /tmp/m9stores >/dev/null 2>&1 &
  TUT_SRV=$!
  # A CLEANUP TRAP MUST NOT DECIDE THE VERDICT.  The status of the
  # trap's last command becomes the script's, so a `kill` of a server
  # that has already exited turned a fully green tutdiff -- every
  # check printed and passed -- into exit 1.  Carry the real status
  # across the cleanup instead.
  trap 'rc=$?; kill $TUT_SRV 2>/dev/null || :; exit $rc' EXIT
  sleep 1
}

tut_pre () {                    # per-example setup before running
  case $1 in C8Zarr|C10Icos|C11Fetch) tut_serve ;; esac
}
