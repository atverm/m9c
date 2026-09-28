# Bits

Bit manipulation on I64, the value read as its 64-bit two's-
complement pattern.  Pre-registered in the report as "unsigned
only" and built on I64 instead, for a measured reason: every place
in this corpus that needed a bit was working on an I64 -- Stats's
generator state, Zarr's little-endian integer bytes, the flag
columns of a station file -- and U64 is the type the generator
serves worst (DIV, MOD and the comparisons still go through the
signed helpers).  A module that only accepted U64 would have made
its callers convert twice around every call, each conversion a
RAISES ValueRange, for no bit of safety in return.

None of these is arithmetic, so none checks for Overflow: a shift
that carries a bit off the top DROPS it, which is what a shift is,
and `Shl (1, 63)` answers the smallest I64 rather than raising.
What IS checked is the shift count -- C leaves a shift by 64 or by
a negative count undefined, and the generator's -O2 would be free
to do anything with it -- so a count outside 0..63 is ValueRange
BY NAME.  The operations themselves are one C operator each,
bound from the runtime header as static inline functions, so the
compiler sees the operator and not a call.

A CHAR or a BYTE goes through I64 (x) and back; they are already
integers with bounds, and the bounds are checked on the way back
exactly where a bit left the range.

### And (a: I64 ; b: I64) : I64

_(documented with the group below)_

### Or (a: I64 ; b: I64) : I64

_(documented with the group below)_

### Xor (a: I64 ; b: I64) : I64

bit by bit over all 64

### Not (a: I64) : I64

every bit flipped: Not (0) = -1, Not (x) = -1 - x

### Shl (a: I64 ; n: I64) : I64 RAISES ValueRange

a moved n bits up, zeros entering below, the top n bits gone;
n outside 0..63 raises

### Shr (a: I64 ; n: I64) : I64 RAISES ValueRange

LOGICAL shift: a moved n bits down with ZEROS entering above, so
Shr (-1, 1) is the largest I64 and Shr (a, 0) is a.  The
arithmetic shift that keeps the sign is `a DIV 2^n` only for a
non-negative a; there is no Sar here because nothing has needed
one.  n outside 0..63 raises

### Test (a: I64 ; bit: I64) : BOOL RAISES ValueRange

whether bit `bit` (0 the lowest, 63 the sign) is set; a bit
number outside 0..63 raises

### Count (a: I64) : I64

the number of set bits in the 64-bit pattern: Count (-1) = 64

The operators, as static inline functions in runtime/m9rt.h -- the
generated C declares each `extern` after including that header,
which C11 reads as the prior internal linkage, so the call inlines
to the operator at any -O.  REENTRANT: pure functions of their
arguments.  The two shifts ASSUME 0..63 -- the check is Bits's, in
M9, where it can raise; the helper has no error slot to raise
through.

### CAnd (a: C.SSizeT ; b: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### COr (a: C.SSizeT ; b: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CXor (a: C.SSizeT ; b: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CNot (a: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CShl (a: C.SSizeT ; n: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CShr (a: C.SSizeT ; n: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CCount (a: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_
