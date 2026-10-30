#!/usr/bin/env python3
"""arrowread.py OUTDIR -- Arrow IPC streams for Arrow.m9's READER, and
what pyarrow reads from each (arrowread.sh compares runtime/test/arrowread/
ArrowRead.m9's text with it).  pyarrow writes every stream and pyarrow
reads it back for the expected text: the oracle is the library zpd and
mcpd's clients use, never the code under test.

NAME.arrows and NAME.want per stream.  The text, one line each:
  fields N
  f I NAME TYPE TZ       TYPE as Arrow.m9's Ty constants
  m KEY=VALUE            the schema metadata for the keys ArrowRead asks
  b ROWS                 per record batch
  c I NULLS              per column of the batch
  v I ROW VALUE          per cell: null, repr () of a float, an int
                         (timestamps as nanoseconds), or the string
A stream the reader must refuse is `refused MESSAGE' after whatever it
printed first.
"""
import os
import sys

import pyarrow as pa
import pyarrow.ipc as ipc

TY = {pa.int8(): 0, pa.int16(): 1, pa.int32(): 2, pa.int64(): 3,
      pa.float32(): 4, pa.float64(): 5, pa.string(): 6}
KEYS = ["passport", "über", "absent"]


def ty_of(t):
    if pa.types.is_timestamp(t):
        return 7, (t.tz or "")
    return TY[t], ""


def text(batches, schema):
    out = ["fields %d" % len(schema)]
    for i, f in enumerate(schema):
        t, tz = ty_of(f.type)
        out.append("f %d %s %d %s" % (i, f.name, t, tz))
    md = {k.decode(): v.decode() for k, v in (schema.metadata or {}).items()}
    for k in KEYS:
        out.append("m %s=%s" % (k, md.get(k, "")))
    for b in batches:
        out.append("b %d" % b.num_rows)
        for i, col in enumerate(b.columns):
            out.append("c %d %d" % (i, col.null_count))
            if pa.types.is_timestamp(col.type):
                vals = col.cast(pa.int64()).to_pylist()
            else:
                vals = col.to_pylist()
            for r, v in enumerate(vals):
                if v is None:
                    s = "null"
                elif isinstance(v, float):
                    s = repr(v)
                else:
                    s = str(v)
                out.append("v %d %d %s" % (i, r, s))
    return "\n".join(out) + "\n"


def write(d, name, batches, schema, compression=None, want=None):
    sink = pa.BufferOutputStream()
    opts = ipc.IpcWriteOptions(compression=compression)
    with ipc.new_stream(sink, schema, options=opts) as w:
        for b in batches:
            w.write_batch(b)
    raw = sink.getvalue().to_pybytes()
    with open(os.path.join(d, name + ".arrows"), "wb") as f:
        f.write(raw)
    if want is None:
        rd = ipc.open_stream(raw)
        want = text(list(rd), rd.schema)
    with open(os.path.join(d, name + ".want"), "w", encoding="utf-8") as f:
        f.write(want)


def main():
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    ts = pa.timestamp("ns")
    tsu = pa.timestamp("ns", tz="UTC")

    # every type, one batch, no nulls; the extremes of each width
    s1 = pa.schema([("i8", pa.int8()), ("i16", pa.int16()), ("i32", pa.int32()),
                    ("i64", pa.int64()), ("f32", pa.float32()), ("f64", pa.float64()),
                    ("s", pa.string()), ("t", ts)],
                   metadata={"passport": "station SE-Htm, 2026", "über": "größe CO₂"})
    b1 = pa.record_batch([
        pa.array([-128, 127, 0], pa.int8()),
        pa.array([-32768, 32767, -1], pa.int16()),
        pa.array([-2147483648, 2147483647, 7], pa.int32()),
        pa.array([-9223372036854775808, 9223372036854775807, -2], pa.int64()),
        pa.array([0.1, -1.5, 3.4028234663852886e38], pa.float32()),
        pa.array([0.1, -0.0, 1e300], pa.float64()),
        pa.array(["Hyltemossa", "été", "CO₂ µmol"]),
        pa.array([0, 1761830400123456789, -1], ts),
    ], schema=s1)
    write(d, "types", [b1], s1)

    # nulls and NaN over two batches, a time zone, an empty string
    s2 = pa.schema([("f", pa.float64()), ("g", pa.float32()), ("n", pa.int32()),
                    ("s", pa.string()), ("t", tsu)])
    bs = [pa.record_batch([
              pa.array([1.25, None, float("nan"), -2.0]),
              pa.array([None, 2.5, float("nan"), 0.0], pa.float32()),
              pa.array([None, -3, 4, None], pa.int32()),
              pa.array(["", None, "Lindcove", "Křešice"]),
              pa.array([None, 1700000000000000000, 5, None], tsu)], schema=s2),
          pa.record_batch([
              pa.array([None] * 9 + [9.0]),
              pa.array([1.0] * 10, pa.float32()),
              pa.array(list(range(10)), pa.int32()),
              pa.array(["x%d" % i for i in range(10)]),
              pa.array(list(range(10)), tsu)], schema=s2)]
    write(d, "nulls", bs, s2)
    # the same, every buffer ZSTD; and an empty batch between two
    write(d, "zstd", bs, s2, compression="zstd")
    empty = pa.record_batch([pa.array([], t.type) for t in s2], schema=s2)
    write(d, "empty", [bs[0], empty, bs[1]], s2, compression="zstd")

    # refused by name
    s3 = pa.schema([("u", pa.uint32())])
    write(d, "unsigned", [pa.record_batch([pa.array([1], pa.uint32())], schema=s3)], s3,
          want="refused arrow: column u is an unsigned integer, which is not read\n")
    dct = pa.array(["a", "b", "a"]).dictionary_encode()
    s4 = pa.schema([("d", dct.type)])
    write(d, "dict", [pa.record_batch([dct], schema=s4)], s4,
          want="refused arrow: column d is dictionary-encoded, which is not read\n")
    s5 = pa.schema([("x", pa.int64())])
    lz = text([], s5)
    write(d, "lz4", [pa.record_batch([pa.array([1, 2, 3])], schema=s5)], s5,
          compression="lz4",
          want=lz + "refused arrow: an LZ4 batch is not read\n")


if __name__ == "__main__":
    main()
