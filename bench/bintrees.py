#!/usr/bin/env python3
"""binary-trees in pure CPython, the same algorithm as BinTrees.m9.

A node is a tuple, which is what a Python programmer would reach for
and which is also the cheapest thing the language has: no class, no
__slots__, no attribute lookup.  It is still an object with a header
and a refcount per node, and that is the point of the benchmark --
this column prices Python's allocator the way the others price theirs.

Run at a smaller depth than the compiled columns, and the runner says
which."""
import sys

MIN_DEPTH = 4


def make(depth):
    if depth > 0:
        return (make(depth - 1), make(depth - 1))
    return (None, None)


def check(node):
    left, right = node
    if left is None:
        return 1
    return 1 + check(left) + check(right)


def main():
    max_depth = int(sys.argv[1]) if len(sys.argv) > 1 else 18
    max_depth = max(MIN_DEPTH + 2, max_depth)
    sys.setrecursionlimit(max_depth * 4 + 100)

    print("stretch tree of depth %d  check: %d"
          % (max_depth + 1, check(make(max_depth + 1))))

    long_lived = make(max_depth)

    depth = MIN_DEPTH
    while depth <= max_depth:
        iters = 1 << (max_depth - depth + MIN_DEPTH)
        total = 0
        for _ in range(iters):
            total += check(make(depth))
        print("%d trees of depth %d  check: %d" % (iters, depth, total))
        depth += 2

    print("long lived tree of depth %d  check: %d"
          % (max_depth, check(long_lived)))


main()
