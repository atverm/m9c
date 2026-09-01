#!/usr/bin/env python3
"""mandelbrot in numpy: the same arithmetic, one row at a time, with
the inner pixel loop replaced by an array operation.

This is the column that says what "just use numpy" is actually worth,
and it is not the same program as the other five: the escape test
cannot exit early per pixel, so it does the full 50 iterations for
every pixel in a row and masks the result.  It does MORE arithmetic
and is still faster than CPython by two orders of magnitude, which is
exactly the trade the library exists to make.

The masking keeps it bit-identical to the scalar versions anyway:
once a pixel has escaped, its z is frozen by the mask instead of
being iterated on, so the value that decides the bit is the value the
scalar loop would have stopped at."""
import sys

import numpy as np

MAXITER = 50
LIMIT = 4.0


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mandel_np.py N OUTFILE")
    n = int(sys.argv[1])
    if n < 8:
        n = 8
    n -= n % 8

    inv = 2.0 / n
    cr = np.arange(n, dtype=np.float64) * inv - 1.5

    rows = [b"P4\n%d %d\n" % (n, n)]
    for y in range(n):
        ci = y * inv - 1.0
        zr = np.zeros(n)
        zi = np.zeros(n)
        live = np.ones(n, dtype=bool)
        for _ in range(MAXITER):
            t = zr * zr - zi * zi + cr
            zi2 = 2.0 * zr * zi + ci
            zr = np.where(live, t, zr)
            zi = np.where(live, zi2, zi)
            live &= (zr * zr + zi * zi) <= LIMIT
        rows.append(np.packbits(live).tobytes())

    with open(sys.argv[2], "wb") as f:
        f.write(b"".join(rows))


main()
