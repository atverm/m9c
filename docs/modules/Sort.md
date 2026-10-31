# Sort

This module sorts over a slice, stable and in place.  So a sub-range
needs no offsets in the signature.  Name the view, then sort it,

    sub := SLICE (a, start, len) ;
    Sort.I64s (sub) ;

and the parent's elements move, since a view shares the buffer.
The two lines are not one.  `Sort.I64s (SLICE (a, 0, n))` is
refused, because a VAR argument must be a designator and a SLICE
expression is not one (probe `var-arg-not-designator`).  The zarr
proxy port hit it on 2026-09-28, after this comment had said
otherwise.

Until 2026-09-27 the corpus exported no sort at all.  Stats kept a
private heapsort, Zarr an insertion sort whose comment said "the
corpus exports none", Json a third, m9edit a fourth.  The ONEFlux
port wrote its own merge sort when a heapsort's instability changed
an answer.  The review of that day counted them
(docs/agent-review-2026-09-27.md F7).  The port asked for exactly
two properties: a sort over a sub-range, and a stable one.  Both
are here, as a merge sort: n log n, stable by construction, the
scratch half in a pool that dies with the call.

`By` is the corpus's first use of a procedure type (report par
2.2.3).  It takes the caller's own order over I64 keys.  A table of
records is sorted by any column this way: sort its row indices
with a Less that reads the column.

### TYPE Less

Less is a strict order.  It answers TRUE when a goes before b and
FALSE for equal keys, which is what keeps the sort stable

### EXCEPTION NotANumber

an F64 sort met a NaN at index `at`: no order holds it, and a
sort that put it somewhere would be inventing one (the Stats
rule, par 2.1)

### F64s (VAR a: SLICE OF F64) RAISES NotANumber

F64s sorts ascending, stable.  -0.0 and 0.0 are equal and keep
their order

### I64s (VAR a: SLICE OF I64)

I64s sorts ascending, stable

### Strs (VAR a: SLICE OF STR)

Strs sorts ascending by scalar value, position by position, the
shorter first when one is a prefix of the other.  It is stable.
It uses no locale: 'B' sorts before 'a'.

Strs is not KEPT, on purpose.  The first version merged through
a scratch SLICE OF STR.  To the checker, `tmp[k] := a[j]` is a
borrowed string stored into another parameter's storage.  The
checker demanded KEPT a, and the mark climbed into every caller.
In the zarr proxy port it climbed from Shuttle.FlatVars up into
SetupRun, a thread root (2026-09-28).  This version sorts an
index permutation (the strings are only READ, through RO).  It
applies the permutation in place through one local, which the
checker sees as movement within the caller's own slice.  It keeps
the same n log n and the same stability, with no scratch
strings.

### ArgF64 (RO v: SLICE OF F64 ; VAR idx: SLICE OF I64) RAISES NotANumber, IndexError

ArgF64 gives the indices 0 .. LEN (v) - 1 in the order that sorts
v, stable: equal values keep index order.  LEN (idx) must be
LEN (v) (IndexError otherwise).  v is not moved

### ArgI64 (RO v: SLICE OF I64 ; VAR idx: SLICE OF I64) RAISES IndexError

_(documented with the group below)_

### ArgStr (RO v: SLICE OF STR ; VAR idx: SLICE OF I64) RAISES IndexError

ArgI64 and ArgStr are ArgF64 for integers and for strings (in
Strs's order).  They give the indices that sort v, stable, and v
is not moved.  LEN (idx) must be LEN (v)

### By (VAR keys: SLICE OF I64 ; less: Less)

By sorts the keys in the caller's order, stable

### UniqueF64 (RO v: SLICE OF F64) : SLICE OF F64 RAISES NotANumber

_(documented with the group below)_

### UniqueI64 (RO v: SLICE OF I64) : SLICE OF I64

_(documented with the group below)_

### UniqueStrs (RO v: SLICE OF STR) : SLICE OF STR

These answer the distinct values of v, ascending: numpy.unique.
The answer is new storage in the caller's frame, and v is not
moved.  The strings of UniqueStrs are copies, so the answer does
not hold on to v.  -0.0 and 0.0 are one value (the first met
stays).  A NaN is NotANumber, as it is for the sort this stands
on.

### LowerF64 (RO a: SLICE OF F64 ; x: F64) : I64

_(documented with the group below)_

### UpperF64 (RO a: SLICE OF F64 ; x: F64) : I64

_(documented with the group below)_

### FindF64 (RO a: SLICE OF F64 ; x: F64) : I64

_(documented with the group below)_

### LowerI64 (RO a: SLICE OF I64 ; x: I64) : I64

_(documented with the group below)_

### UpperI64 (RO a: SLICE OF I64 ; x: I64) : I64

_(documented with the group below)_

### FindI64 (RO a: SLICE OF I64 ; x: I64) : I64

_(documented with the group below)_

### FindStr (RO a: SLICE OF STR ; RO s: STR) : I64

These do a BINARY SEARCH in a slice that is ASCENDING.  The
caller must ensure the order.  These read about log2 (LEN (a))
elements and cannot notice a slice that is not sorted.

  Lower:  the first index whose element is not less than x,
          0 .. LEN (a): where x would be inserted to stay
          before its equals (numpy.searchsorted, side='left')
  Upper:  the first index whose element is greater than x:
          after its equals (side='right').  Upper - Lower is
          how many elements equal x.
  Find:   the index of the FIRST element equal to x, or -1

A NaN x is after everything, as numpy has it: Lower and Upper
answer LEN (a), and Find -1.

csort binds the LSD radix sorts of runtime/m9rt.c (m9rt.h).  They
sort a slice's storage, stable, and answer 1 when done and 0 when
the caller's merge sort must do it.  There is no LINK: the sorts
are the runtime's.  They are REENTRANT: their scratch comes from
malloc, and they share no state.  CArgUtf orders a slice of STRs by
their octets: the radix sort over an eight-byte prefix, then memcmp
where the prefixes agree.

### CSortF64 (a: C.MutPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_

### CSortI64 (a: C.MutPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_

### CArgF64 (v: C.ConstPtr ; idx: C.MutPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_

### CArgI64 (v: C.ConstPtr ; idx: C.MutPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_

### CArgUtf (v: C.ConstPtr ; idx: C.MutPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_
