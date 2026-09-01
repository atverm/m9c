#!/usr/bin/env python3
"""The reference column of the CSV benchmark: polars and pandas on the
same file M9 reads, timed the same way.

Two polars columns, because M9 has no threads and polars has all of
them.  POLARS_MAX_THREADS=1 is the like-for-like comparison; the
multi-core number is reported beside it as the thing a single-threaded
reader cannot match today, rather than left out because it is
unflattering.

Float32 throughout, because that is what the instruments have and what
the M9 reader parses to -- a Float64 schema would be a different
amount of work and a different benchmark.

THE SCHEMA IS GIVEN, NOT INFERRED, and not to be kind to polars: with
its default inference this file does not read at all.  Hundreds of
FLUXNET columns are -9999 for their first thousands of rows, so
polars types them i64 and then fails 125 KB in --

  ComputeError: could not parse `-2.03` as dtype `i64` at column
  'G_F_MDS' (column number 76)

-- which is the same hazard the M9 reader answers by making the
caller state each column's kind.  Both sides are therefore told the
schema, and both do the same work."""
import os
import sys
import time

PATH = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fluxnet.csv"
REPS = 3
STAMPS = ("TIMESTAMP_START", "TIMESTAMP_END")


def best(fn, reps=REPS):
    fn()                       # warm the page cache and the imports
    out = 1e9
    for _ in range(reps):
        t0 = time.perf_counter()
        fn()
        out = min(out, time.perf_counter() - t0)
    return out


def header(path):
    with open(path, "r") as f:
        return f.readline().rstrip("\n").rstrip("\r").split(",")


def main():
    import polars as pl

    cols = header(PATH)
    schema = {c: (pl.Int64 if c in STAMPS else pl.Float32) for c in cols}
    nthreads = pl.thread_pool_size()

    def read_polars():
        return pl.read_csv(PATH, schema=schema)

    t = best(read_polars)
    df = read_polars()
    print("polars   read_csv, given schema   %6.2f s   %2d thread(s)  "
          "%d x %d" % (t, nthreads, df.height, df.width))

    if os.environ.get("WITH_PANDAS"):
        import pandas as pd
        dt = {c: ("int64" if c in STAMPS else "float32") for c in cols}

        def read_pandas():
            return pd.read_csv(PATH, dtype=dt, engine="c", low_memory=False)
        t = best(read_pandas, 1)
        print("pandas   read_csv, given dtype   %6.2f s    1 thread" % t)


main()
