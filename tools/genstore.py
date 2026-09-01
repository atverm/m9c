#!/usr/bin/env python3
"""Regenerate the P4 differential-test zarr stores.

The goldens they must reproduce are in runtime/test/zarr_driver.c,
each with its provenance.

Both recipes were re-derived from the goldens and verified to the
last digit on 2026-08-21 (corner values, counts, and bench nansum are
exact; whole-array aggregates like nanmean depend on reduction order
and are defined by the FPC oracle's sequential order, not numpy's
pairwise one).

Requires: numpy, zarr<3 (v2 store layout), numcodecs (blosc).
Usage: python3 genstore.py [outdir]   (default ./stores)
"""
import os
import shutil
import sys

import numpy as np
import zarr

assert zarr.__version__ < "3", "zarr<3 required: the readers speak v2"


def co2_store(root):
    """100x50 f8, chunks 30x20, blosc lz4; NaN at [10,5]; chunk 2.1
    (rows 60:90 x cols 20:40) deleted after write.
    data = 380 + 40*rand, seed 42."""
    path = os.path.join(root, "co2.zarr")
    shutil.rmtree(path, ignore_errors=True)
    np.random.seed(42)
    d = 380 + 40 * np.random.rand(100, 50)
    d[10, 5] = np.nan
    z = zarr.open(path, mode="w", shape=(100, 50), chunks=(30, 20),
                  dtype="<f8", compressor=zarr.Blosc(cname="lz4"),
                  fill_value=np.nan)   # deleted chunk must READ as NaN:
                                       # n=4399 golden proves this fill
    z[:] = d
    os.remove(os.path.join(path, "2.1"))
    # goldens (exact)
    assert repr(float(d[0, 0])) == "394.9816047538945"
    assert repr(float(d[99, 49])) == "403.89249513322846"
    assert repr(float(d[42, 17])) == "404.6119210027921"
    dd = d.copy()
    dd[60:90, 20:40] = np.nan
    assert int(np.isfinite(dd).sum()) == 4399
    print("co2.zarr written; corner goldens and n=4399 verified")


def bench_store(root):
    """4000x4000 f8, chunks 500x500, blosc lz4; NaN where the uniform
    draw is < 0.0125 (i.e. value < 380.5).  data = 380 + 40*u, seed 1."""
    path = os.path.join(root, "bench.zarr")
    shutil.rmtree(path, ignore_errors=True)
    np.random.seed(1)
    u = np.random.rand(4000, 4000)
    b = 380 + 40 * u
    b[u < 0.0125] = np.nan
    z = zarr.open(path, mode="w", shape=(4000, 4000), chunks=(500, 500),
                  dtype="<f8", compressor=zarr.Blosc(cname="lz4"))
    z[:] = b
    n = int(np.isfinite(b).sum())
    s = float(np.nansum(b))
    assert n == 15800721, n
    assert repr(s) == "6324247734.661942", repr(s)
    print("bench.zarr written; nansum and n goldens verified")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "stores"
    os.makedirs(root, exist_ok=True)
    co2_store(root)
    bench_store(root)
    print("stores in", os.path.abspath(root),
          "(not for the repo: ~102MB)")


if __name__ == "__main__":
    main()
