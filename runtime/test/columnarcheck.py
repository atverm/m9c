#!/usr/bin/env python3
"""Parquet.m9 and NetCDF.m9's WRITERS judged by readers M9 did not write.

    columnarcheck.py parquet DIR    pyarrow reads DIR/opt.parquet, DIR/plain.parquet
    columnarcheck.py netcdf DIR     netCDF4-python reads DIR/grid.nc, DIR/text.nc

The files are what runtime/test/columnarout.m9 wrote (columnar.sh runs
both); the values it wrote are stated again here, by hand, and the two
statements must agree.  A writer is right when somebody else's reader
says so: this is the outside witness, corpus/ParquetTest.m9 and
NetCDFTest.m9 hold the same files through M9's own readers.

Prints one FAIL line per disagreement and `PASS (n checks) -- NAME`, or
`SKIP: ...` when the reader is not installed; exits 1 on any FAIL."""
import math
import struct
import sys

checks = 0
fails = 0


def ok(what, cond):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print("FAIL: " + what)


def done(name):
    if fails:
        print(f"FAILED {fails} of {checks} -- {name}")
        sys.exit(1)
    print(f"PASS ({checks} checks) -- {name}")


ROWS = 10


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def bits32(x):
    return struct.pack("<f", x)


# ---- the frame columnarout.m9 writes, stated again -----------------------

TA = [f32(r * 0.25 - 1.0) for r in range(ROWS)]
TA[3] = TA[7] = None                       # NaN: missing
SW = [100.0 + r * 0.5 for r in range(ROWS)]
SW[1] = None                               # the sentinel -9999.0: missing
SW[5] = None                               # NaN: missing
SW_PLAIN = [100.0 + r * 0.5 for r in range(ROWS)]
SW_PLAIN[1] = -9999.0
SW_PLAIN[5] = float("nan")
QC = [-3, -2, -1, 0, None, 1, 2, 3, 127, -128]
Q16 = [r % 4 for r in range(ROWS)]
H = [r * 1000 - 4000 for r in range(ROWS)]
H[2] = None
N = [r * r * 1000000007 - 5 for r in range(ROWS)]
N[9] = None
B = [r * 25 for r in range(ROWS)]
B[0] = None
NOTE = ["", "ok", "°C", "µmol m-2 s-1", "a", "b", "c", "d", "e", "f"]
DAY = [r % 3 == 0 for r in range(ROWS)]
US = [1672531200000000 + r * 1800000000 for r in range(ROWS)]
NS = [u * 1000 for u in US]
COLUMNS = ["TA", "SW", "QC", "Q16", "H", "N", "B", "NOTE", "DAY", "time", "tns"]


def same_reals(got, want, width):
    """None for None, NaN for NaN, else the same bits at the width"""
    if len(got) != len(want):
        return False
    for g, w in zip(got, want):
        if w is None or g is None:
            if g is not w:
                return False
        elif isinstance(w, float) and math.isnan(w):
            if not (isinstance(g, float) and math.isnan(g)):
                return False
        elif width == 32:
            if bits32(g) != bits32(w):
                return False
        elif struct.pack("<d", g) != struct.pack("<d", w):
            return False
    return True


def parquet(d):
    try:
        import pyarrow as pa
        import pyarrow.parquet as pq
    except ImportError:
        print("SKIP: pyarrow not installed")
        return
    t = pq.read_table(d + "/opt.parquet")
    md = pq.ParquetFile(d + "/opt.parquet").metadata
    ok("opt: the columns in order", t.column_names == COLUMNS)
    ok("opt: ten rows", t.num_rows == ROWS)
    want = {"TA": pa.float32(), "SW": pa.float64(), "QC": pa.int8(), "Q16": pa.int8(),
            "H": pa.int16(), "N": pa.int64(), "B": pa.uint8(), "NOTE": pa.string(),
            "DAY": pa.bool_(), "time": pa.timestamp("us"), "tns": pa.timestamp("ns", tz="UTC")}
    for c in COLUMNS:
        ok(f"opt: {c} is {want[c]} (pyarrow says {t.schema.field(c).type})",
           t.schema.field(c).type == want[c])
    # the logical type said, not inferred: INT(8, signed), TIMESTAMP's unit and zone
    sch = md.schema
    for i, c in enumerate(COLUMNS):
        col = sch.column(i)
        if c in ("QC", "Q16"):
            ok(f"opt: {c} is INT32 annotated INT(8, signed) ({col.logical_type}, {col.converted_type})",
               col.physical_type == "INT32" and col.converted_type == "INT_8")
        if c == "time":
            lt = col.logical_type.to_json()
            ok(f"opt: time is TIMESTAMP(MICROS, not adjusted to UTC) ({lt})",
               col.physical_type == "INT64" and '"timeUnit": "microseconds"' in lt
               and '"isAdjustedToUTC": false' in lt)
        if c == "tns":
            lt = col.logical_type.to_json()
            ok(f"opt: tns is TIMESTAMP(NANOS, adjusted to UTC) ({lt})",
               '"timeUnit": "nanoseconds"' in lt and '"isAdjustedToUTC": true' in lt)
        nullable = c not in ("NOTE", "DAY")
        ok(f"opt: {c} is {'OPTIONAL' if nullable else 'REQUIRED'}",
           (col.max_definition_level == 1) == nullable)
    ok("opt: TA, NaN cells null, the rest to the bit",
       same_reals(t.column("TA").to_pylist(), TA, 32))
    ok("opt: SW, the sentinel AND the NaN null",
       same_reals(t.column("SW").to_pylist(), SW, 64))
    for c, v in (("QC", QC), ("Q16", Q16), ("H", H), ("N", N), ("B", B)):
        got = t.column(c).to_pylist()
        ok(f"opt: {c} = {v} (pyarrow reads {got})", got == v)
    ok("opt: NOTE, UTF-8 and the empty string a value, not null",
       t.column("NOTE").to_pylist() == NOTE)
    ok("opt: DAY", t.column("DAY").to_pylist() == DAY)
    ok("opt: time, microseconds since the epoch",
       t.column("time").cast(pa.int64()).to_pylist() == US)
    ok("opt: tns, nanoseconds", t.column("tns").cast(pa.int64()).to_pylist() == NS)
    ok("opt: the null count is the missing cells and no more",
       sum(t.column(c).null_count for c in COLUMNS) == 2 + 2 + 1 + 1 + 1 + 1)
    kv = md.metadata or {}
    ok("opt: key-value metadata, UTF-8 beyond ASCII",
       kv.get(b"icos_u_pid") == b"11676/U/test"
       and kv.get(b"units") == "°C and µmol m-2 s-1".encode("utf-8"))

    # nothing asked: WriteX's file, REQUIRED columns, the missing cells as values
    p = pq.read_table(d + "/plain.parquet")
    psch = pq.ParquetFile(d + "/plain.parquet").metadata.schema
    ok("plain: every column REQUIRED",
       all(psch.column(i).max_definition_level == 0 for i in range(len(COLUMNS))))
    ok("plain: no null anywhere", sum(p.column(c).null_count for c in COLUMNS) == 0)
    ok("plain: SW holds the sentinel and the NaN as values",
       same_reals(p.column("SW").to_pylist(), SW_PLAIN, 64))
    ok("plain: QC is int32 with its sentinel",
       p.schema.field("QC").type == pa.int32() and p.column("QC").to_pylist()[4] == -2147483648)
    ok("plain: time is a bare int64", p.schema.field("time").type == pa.int64())
    ok("plain: no key-value metadata", not pq.ParquetFile(d + "/plain.parquet").metadata.metadata)
    done("columnar parquet (pyarrow reads M9)")


def netcdf(d):
    try:
        import netCDF4
        import numpy as np
    except ImportError:
        print("SKIP: netCDF4 not installed")
        return
    with netCDF4.Dataset(d + "/grid.nc") as nc:
        nc.set_auto_maskandscale(False)
        ok("grid: a classic file", nc.data_model == "NETCDF3_CLASSIC")
        ok("grid: lat 4, lon 5", {k: len(v) for k, v in nc.dimensions.items()} == {"lat": 4, "lon": 5})
        v = nc.variables["t2m"]
        ok("grid: t2m double on (lat, lon)", v.dtype == np.float64 and v.dimensions == ("lat", "lon"))
        want = np.array([[100.0 * i + j / 8.0 for j in range(5)] for i in range(4)])
        ok("grid: every value to the bit", np.array_equal(v[:], want))
        ok("grid: a hyperslab reads the row it names", np.array_equal(v[2, :], want[2]))
        ok("grid: units K, a real one-octet text attribute",
           v.getncattr("units") == "K" and att_bytes(d + "/grid.nc", "t2m", "units") == b"K")
        ok("grid: scale_factor 0.5, a double", v.getncattr("scale_factor") == 0.5
           and np.asarray(v.getncattr("scale_factor")).dtype == np.float64)
        ok("grid: the global title", nc.getncattr("title") == "written by M9")
    with netCDF4.Dataset(d + "/text.nc") as nc:
        nc.set_auto_maskandscale(False)
        ok("text: netCDF-4", nc.data_model == "NETCDF4")
        ta, qc = nc.variables["TA"], nc.variables["QC"]
        # the attribute's OCTETS, as the C library holds them: nc_get_att_text through ctypes
        raw = att_bytes(d + "/text.nc", "TA", "units")
        ok(f"text: TA units are the UTF-8 octets C2 B0 43 (got {raw.hex(' ') if raw else raw})",
           raw == b"\xc2\xb0C")
        ok("text: and netCDF4-python decodes them to °C", ta.getncattr("units") == "°C")
        ok("text: TA long_name", ta.getncattr("long_name") == "air temperature")
        raw = att_bytes(d + "/text.nc", None, "title")
        ok("text: the global title, UTF-8 octets",
           raw == "µmol m-2 s-1 — a title".encode("utf-8"))
        ok("text: ASCII through PutAttText", nc.getncattr("plain") == "ASCII only")
        ok("text: PutAttStr still writes octets", att_bytes(d + "/text.nc", None, "octets") == b"K and m")
        ok("text: TA float, the NaN fill", ta.dtype == np.float32 and math.isnan(ta.getncattr("_FillValue")))
        want = np.array([r * 0.25 - 1.0 for r in range(ROWS)], dtype=np.float32)
        got = ta[:]
        ok("text: TA's values, NaN where written", math.isnan(got[3])
           and np.array_equal(np.delete(got, 3), np.delete(want, 3)))
        ok("text: QC a signed byte, negative values kept",
           qc.dtype == np.int8 and list(qc[:]) == [r - 5 for r in range(ROWS)])
    done("columnar netcdf (netCDF4-python reads M9)")


def att_bytes(path, var, name):
    """an NC_CHAR attribute's octets straight from libnetcdf (nc_get_att_text):
    netCDF4-python would decode them, and a decoder can hide a wrong byte"""
    import ctypes
    import ctypes.util
    lib = ctypes.CDLL(ctypes.util.find_library("netcdf"))
    ncid = ctypes.c_int()
    if lib.nc_open(path.encode(), 0, ctypes.byref(ncid)) != 0:
        return None
    try:
        varid = ctypes.c_int(-1)
        if var is not None and lib.nc_inq_varid(ncid, var.encode(), ctypes.byref(varid)) != 0:
            return None
        n = ctypes.c_size_t()
        if lib.nc_inq_attlen(ncid, varid, name.encode(), ctypes.byref(n)) != 0:
            return None
        buf = ctypes.create_string_buffer(n.value)
        if lib.nc_get_att_text(ncid, varid, name.encode(), buf) != 0:
            return None
        return buf.raw[:n.value]
    finally:
        lib.nc_close(ncid)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("parquet", "netcdf"):
        sys.exit(__doc__)
    (parquet if sys.argv[1] == "parquet" else netcdf)(sys.argv[2])
