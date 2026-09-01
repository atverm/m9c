#!/usr/bin/env python3
"""fannkuch-redux in pure CPython, the same algorithm as Fannkuch.m9.

Python's lists are bounds-checked and its integers do not overflow at
all -- they grow -- so this column is the maximum of the safety on
offer anywhere in the comparison, at the price the interpreter
charges.  It is run at a smaller n than the compiled columns and the
runner says so; fannkuch is O(n!) and n=11 in CPython is a coffee
break, not a benchmark.

The flip and the rotation are slice assignments rather than the
element-wise loops the other five use.  That is deliberate and it is
the only fair way to run this column: a Python programmer writes
`perm[:k+1] = perm[k::-1]`, and writing the loop instead would be
benchmarking my willingness to handicap the language rather than the
language."""
import sys


def run(n):
    perm1 = list(range(n))
    perm = [0] * n
    count = [0] * n
    r = n
    max_flips = 0
    perm_count = 0
    checksum = 0
    while True:
        while r != 1:
            count[r - 1] = r
            r -= 1
        perm[:] = perm1
        flips = 0
        k = perm[0]
        while k != 0:
            perm[: k + 1] = perm[k::-1]
            flips += 1
            k = perm[0]
        if flips > max_flips:
            max_flips = flips
        if perm_count % 2 == 0:
            checksum += flips
        else:
            checksum -= flips
        perm_count += 1
        while True:
            if r == n:
                return checksum, max_flips
            p0 = perm1[0]
            perm1[:r] = perm1[1 : r + 1]
            perm1[r] = p0
            count[r] -= 1
            if count[r] > 0:
                break
            r += 1


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    n = max(1, min(16, n))
    checksum, max_flips = run(n)
    print(checksum)
    print("Pfannkuchen(%d) = %d" % (n, max_flips))


main()
