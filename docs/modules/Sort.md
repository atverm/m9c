# Sort

Sorting, stable, in place, over a slice -- so a sub-range needs no
offsets in the signature: name the view, then sort it,

    sub := SLICE (a, start, len) ;
    Sort.I64s (sub) ;

and the parent's elements move, since a view shares the buffer.
The two lines are not one: `Sort.I64s (SLICE (a, 0, n))` is
refused, because a VAR argument must be a designator and a SLICE
expression is not one (probe `var-arg-not-designator`; the zarr
proxy port hit it on 2026-09-28 after this comment had said
otherwise).

Until 2026-09-27 the corpus exported no sort at all: Stats kept a
private heapsort, Zarr an insertion sort whose comment said "the
corpus exports none", Json a third, m9edit a fourth, and the
ONEFlux port wrote its own merge sort when a heapsort's instability
changed an answer.  The review of that day counted them
(docs/agent-review-2026-09-27.md F7) and the port asked for exactly
two properties: a sort over a sub-range, and a stable one.  Both
are here, as a merge sort: n log n, stable by construction, the
scratch half in a pool that dies with the call.

`By` is the corpus's first use of a procedure type (report par
2.2.3): the caller's own order over I64 keys, which is how a table
of records is sorted by any column -- sort its row indices with a
Less that reads the column.

### TYPE Less

a strict order: TRUE when a goes before b, FALSE for equal keys,
which is what keeps the sort stable

### EXCEPTION NotANumber

an F64 sort met a NaN at index `at`: no order holds it, and a
sort that put it somewhere would be inventing one (the Stats
rule, par 2.1)

### F64s (VAR a: SLICE OF F64) RAISES NotANumber

ascending, stable; -0.0 and 0.0 are equal and keep their order

### I64s (VAR a: SLICE OF I64)

ascending, stable

### Strs (VAR a: SLICE OF STR)

ascending by scalar value, position by position, the shorter
first when one is a prefix of the other; stable.  No locale:
'B' sorts before 'a'.

Not KEPT, on purpose.  The first version merged through a
scratch SLICE OF STR, and `tmp[k] := a[j]` is, to the checker,
a borrowed string stored into another parameter's storage: it
demanded KEPT a, and the mark climbed into every caller -- in
the zarr proxy port from Shuttle.FlatVars up into SetupRun, a
thread root (2026-09-28).  This version
sorts an index permutation (the strings are only READ, through
RO) and applies it in place through one local, which the
checker sees as movement within the caller's own slice.  Same
n log n, same stability, no scratch strings.

### ArgF64 (RO v: SLICE OF F64 ; VAR idx: SLICE OF I64) RAISES NotANumber, IndexError

the indices 0 .. LEN (v) - 1 in the order that sorts v, stable:
equal values keep index order.  LEN (idx) must be LEN (v)
(IndexError otherwise); v is not moved

### By (VAR keys: SLICE OF I64 ; less: Less)

the keys in the caller's order, stable
