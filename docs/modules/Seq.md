# Seq

Growable lists and the slice-of-string operations a program would
otherwise write again each time (2026-10-10, cp-kernel's proposal:
its kernel wrote the count-allocate-fill pattern -- one loop counts,
NEW, a second loop fills -- and its own Copy/Distinct/Concat).

A list is a record the caller owns, its storage in a POOL the caller
names at every Add, so the list lives exactly as long as that pool:

    VAR names : Seq.Strs ;
    ...
    Seq.AddStr (pool, names, s) ;      (* one pass, no count first *)
    ...
    FOR i := 0 TO Seq.LenStrs (names) - 1 DO ... names.at[i] ... END

`at' holds the elements in 0 .. n - 1; room beyond n is unused.
Room doubles when full, so n Adds copy each element at most twice
on average.  A string added is COPIED into the pool (as
Sort.UniqueStrs copies): the list never holds the caller's view, so
adding asks no KEPT of the caller.

No generics: one record and one Add per element type -- STR, I64,
F64 -- which is three twins of each, counted for the generics
question as Sort's were.

### TYPE Strs

_(documented with the group below)_

### TYPE I64s

_(documented with the group below)_

### TYPE F64s

_(documented with the group below)_

### AddStr (VAR pool: POOL ; VAR s: Strs ; RO v: STR)

_(documented with the group below)_

### AddI64 (VAR pool: POOL ; VAR s: I64s ; v: I64)

_(documented with the group below)_

### AddF64 (VAR pool: POOL ; VAR s: F64s ; v: F64)

v appended; room grown in pool when full.  Every Add on one list
names the same pool.

### LenStrs (RO s: Strs) : I64

_(documented with the group below)_

### LenI64s (RO s: I64s) : I64

_(documented with the group below)_

### LenF64s (RO s: F64s) : I64

_(documented with the group below)_

### StrsOf (VAR pool: POOL ; RO s: Strs) : SLICE OF STR

_(documented with the group below)_

### I64sOf (VAR pool: POOL ; RO s: I64s) : SLICE OF I64

_(documented with the group below)_

### F64sOf (VAR pool: POOL ; RO s: F64s) : SLICE OF F64

the elements as a slice of exactly n, in pool, the strings
copied: what a procedure taking a SLICE wants, and it outlives
the list if pool does

### Copy (VAR pool: POOL ; RO xs: SLICE OF STR) : SLICE OF STR

xs in its order, the slice and every string copied into pool

### Concat (VAR pool: POOL ; RO a, b: SLICE OF STR) : SLICE OF STR

a then b, copied into pool

### Distinct (VAR pool: POOL ; RO xs: SLICE OF STR) : SLICE OF STR

each string once, in the order first seen, copied into pool --
Python's list (dict.fromkeys (xs)).  Sort.UniqueStrs is the SORTED
form.  A sorted index, so n log n, not a scan per element.
