# tutcommon: shared by tutgen.sh and tutdiff.sh -- SOURCED, not run,
# which is why it has no execute bit (the gen.sh precedent).  One
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
  m=$1
  case $m in
  C8Zarr)
    ( cd "$W" && tut_make -c -k "$EXA/$m.m9" ) || return 1
    ( cd "$W" && gcc -O2 -flto "$m.o" ZarrStore.o Json.o Http.o \
        DynStr.o Io.o Fmt.o "$RT/m9rt.c" "$RT/tcpshim.c" "$RT/tlsshim.c" \
        -iquote "$RT" -l:libblosc.so.1 -lssl -lcrypto -lm -o "$m" \
        2>/dev/null ) || return 1 ;;
  C10Icos)
    ( cd "$W" && tut_make -c -k "$EXA/$m.m9" ) || return 1
    ( cd "$W" && gcc -O2 -flto "$m.o" ZarrStore.o Json.o Http.o \
        Mat.o Math.o Plot.o DynStr.o Io.o Fmt.o \
        "$RT/m9rt.c" "$RT/tcpshim.c" "$RT/tlsshim.c" "$RT/fmtshim.c" \
        -iquote "$RT" -l:libblosc.so.1 -lssl -lcrypto -lm -o "$m" \
        2>/dev/null ) || return 1 ;;
  C9Plot)
    ( cd "$W" && tut_make -c -k "$EXA/$m.m9" ) || return 1
    ( cd "$W" && gcc -O2 -flto "$m.o" Plot.o Mat.o Math.o DynStr.o Io.o \
        "$RT/m9rt.c" "$RT/fmtshim.c" -iquote "$RT" -lm -o "$m" \
        2>/dev/null ) || return 1 ;;
  *)
    ( cd "$W" && tut_make -o "$m" "$EXA/$m.m9" -I "$EXA" ) || return 1 ;;
  esac
}

TUT_SRV=
tut_serve () {                  # the zarr chapters' local stores
  [ -n "$TUT_SRV" ] && return 0
  mkdir -p /tmp/m9stores
  [ -d /tmp/m9stores/co2.zarr ] || \
    cp -r "$EXA/data/co2.zarr" /tmp/m9stores/
  [ -d /tmp/m9stores/icos-obspack.zarr ] || \
    cp -r "$EXA/data/icos-obspack.zarr" /tmp/m9stores/
  python3 -m http.server 18931 --bind 127.0.0.1 \
      --directory /tmp/m9stores >/dev/null 2>&1 &
  TUT_SRV=$!
  trap 'kill $TUT_SRV 2>/dev/null' EXIT
  sleep 1
}

tut_pre () {                    # per-example setup before running
  case $1 in C8Zarr|C10Icos) tut_serve ;; esac
}
