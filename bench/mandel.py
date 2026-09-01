#!/usr/bin/env python3
"""mandelbrot in pure CPython: the same algorithm as Mandel.m9,
statement for statement.

It is here for scale, not for a race.  The interesting number is not
that it loses -- everyone knows it loses -- but by how much, and
whether the factor is constant as N grows.  It is run at small N only;
the runner extrapolates and says so rather than pretending it ran the
big one."""
import sys

MAXITER = 50
LIMIT = 4.0


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mandel.py N OUTFILE")
    n = int(sys.argv[1])
    if n < 8:
        n = 8
    n -= n % 8

    out = bytearray(b"P4\n%d %d\n" % (n, n))
    inv = 2.0 / n

    for y in range(n):
        ci = y * inv - 1.0
        for x in range(0, n, 8):
            bits = 0
            for k in range(8):
                cr = (x + k) * inv - 1.5
                zr = 0.0
                zi = 0.0
                bit = 1
                for _ in range(MAXITER):
                    t = zr * zr - zi * zi + cr
                    zi = 2.0 * zr * zi + ci
                    zr = t
                    if zr * zr + zi * zi > LIMIT:
                        bit = 0
                        break
                bits = bits * 2 + bit
            out.append(bits)

    with open(sys.argv[2], "wb") as f:
        f.write(out)


main()
