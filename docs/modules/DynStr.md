# DynStr

Growable strings.  The M2 version leaned on libc malloc/realloc
and answered questions about NIL with quiet zeros (Len (NIL) = 0,
CharAt out of range = 0C).  Here the pool owns the string, NIL
does not exist, and reading is a checked slice, not a CharAt
loop.  Dispose is gone: free the pool, free the strings.

### TYPE DString

opaque; lives in a POOL

### New (VAR pool: POOL) : PTR DString IN pool

an empty string, sixteen characters of capacity, owned by pool.

pool -- where the string and every buffer it later outgrows
        are carved.  The result is `IN pool`, so the checker
        refuses to let it outlive the pool it came from; that
        is why there is no Dispose.

### AppendChar (VAR pool: POOL ; VAR d: PTR DString ; ch: CHAR)

one scalar onto the end, growing the buffer when it is full.

d  -- VAR because growing REPLACES the buffer; a caller
      holding an old View sees the old bytes, which is the
      one thing to know about this type.
ch -- any Unicode scalar.  No encoding happens here: CHAR is
      the unit, and octets are Bytes' business.

### Append (VAR pool: POOL ; VAR d: PTR DString ; RO s: STR)

the whole of s onto the end, one AppendChar at a time.

s -- BORROWED for the call and copied, so appending a View of
     d to d itself is the aliasing case this does not handle;
     nothing in the corpus does it, and the copy is what
     would make it safe.

### Len (d: PTR DString) : I64

characters written so far, never the capacity.  The M2 version
answered 0 for NIL; there is no NIL here, so this cannot be the
quiet zero that hid an unallocated string.

### View (d: PTR DString) : STR

the whole content, zero-copy; replaces the M2 CharAt-in-a-loop
and its out-of-range 0C lie -- indexing the view is checked.

### Equal (d: PTR DString ; RO s: STR) : BOOL

content comparison against a plain slice, without building a
View first.  Eq below is the slice-to-slice form; this one
exists because comparing a builder against a literal is the
common case and should not need two calls.

### Eq (RO a: STR ; RO b: STR) : BOOL

slice-to-slice equality.  Json and ZarrStore had each grown a
private copy before HttpServer became the third caller --
inventory before manufacturing, consolidated here.

### AppendI64 (VAR pool: POOL ; VAR d: PTR DString ; v: I64)

decimal text of v.  Negating MIN(I64) traps Overflow (par 2.1);
no caller formats it today, and the trap is declared behavior,
not a surprise.

### Bytes (VAR pool: POOL ; RO s: STR ; zeroTerm: BOOL) : SLICE OF BYTE RAISES ValueRange

CHAR is a scalar, the wire is octets; a scalar past 255 raises
here, at the boundary, not as mojibake at the peer.  Pool
storage is defined-zero (par 4.3): when zeroTerm is asked for,
the terminator is already in place.

### Utf8 (VAR pool: POOL ; RO s: STR) : SLICE OF BYTE RAISES ValueRange

CHARs as UTF-8 octets -- the OTHER wire.  Bytes above is the
Latin-1 wire and raises past 255; this one encodes every
Unicode scalar (the claim Io.PutChars makes for the console).
The declared ValueRange is the BYTE conversions the checker
counts; every operand is arithmetic mod 64 plus an offset
below 248, so it cannot fire -- declared because the
accounting is exhaustive, not because it happens.  Demanded by
the zarr proxy, whose JSON reference emits ensure_ascii=False.

### Chars (VAR pool: POOL ; RO b: SLICE OF BYTE) : STR RAISES ValueRange

octets to scalars, the inverse of Bytes.  An octet is always a
scalar, so this cannot raise; the checker cannot know that
without byte-level typing (P2 pass 3), and an honest signature
beats a silent assumption.

### FromUtf8 (VAR pool: POOL ; RO b: SLICE OF BYTE) : STR RAISES ValueRange

UTF-8 octets decoded to scalars -- the inverse of Utf8, and
STRICT: an invalid sequence (bad lead or continuation byte,
overlong form, surrogate, past U+10FFFF, truncated tail)
RAISES ValueRange rather than guessing, because a file that is
not UTF-8 read as if it were is the double-encoding bug this
was built to end.  Demanded by the zarr proxy against the REAL
stores: their .zattrs citations carry accented names, and
reading those files through the Latin-1 ReadFile then encoding
with Utf8 emitted every one twice-encoded -- a corruption the
ASCII-only gate stores could never show.
