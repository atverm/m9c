# DynUtf

Growable UTF-8 text: DynStr's twin for UTF (docs/utfbuilder-plan.md),
with DynStr's names, so that a module moves from one to the other by
its qualifier.  It takes over DynStr's name when STR becomes UTF-8.

The buffer holds octets -- a quarter of DynStr's for ASCII -- and only
whole UTF-8 sequences: every writer below appends a UTF, one encoded
scalar or ASCII digits.  Text comes back as a COPY (View, ViewIn),
because a UTF view of octets this module still writes would be the
hole UTF (b) copies against; the octets come back as a read-only view
(Octets), for what leaves as octets anyway.

### TYPE DString

opaque; lives in a POOL

### New (VAR pool: POOL) : PTR DString IN pool

an empty text, sixteen octets of room, owned by pool -- where the
text and every buffer it outgrows are carved

### Append (VAR d: PTR DString ; RO s: UTF)

the octets of s onto the end, growing the buffer when it is full.
d -- VAR because growing REPLACES the buffer; an Octets view
     taken before still reads the old octets.
s -- copied; appending d's own View to d is safe, it is a copy

### AppendChar (VAR d: PTR DString ; ch: CHAR)

one scalar, encoded: one to four octets

### AppendI64 (VAR d: PTR DString ; v: I64)

the decimal text of v, a minus sign first when negative; MIN (I64)
included

### AppendStr (VAR d: PTR DString ; RO s: STR)

the scalars of s, encoded: the bridge for a module that has moved
to DynUtf and meets one that has not.  Goes when STR becomes UTF

### BLen (d: PTR DString) : I64

the octets written so far, never the room, O(1)

### View (d: PTR DString) : UTF

the text so far, COPIED into the caller's frame, O(n).  The octets
are validated as the copy is made; since nothing writes a part of a
character they cannot fail, and were they to, the answer is an
IndexError, never a wrong text

### ViewIn (VAR pool: POOL ; d: PTR DString) : UTF

View, the copy made in pool: for text stored into a structure that
outlives the frame

### Octets (d: PTR DString) : SLICE OF BYTE

the octets so far, a read-only VIEW of the buffer, O(1): for a file,
a hash or a socket.  Valid until the next append that grows it

### Equal (d: PTR DString ; RO s: UTF) : BOOL

the text so far equals s, octet by octet, with no copy

### Bytes (VAR pool: POOL ; RO u: UTF ; zeroTerm: BOOL) : SLICE OF BYTE RAISES ValueRange

DynStr.Bytes's contract, the inverse of Chars: ONE OCTET PER
CHARACTER, a character past 255 refused as ValueRange, in pool,
with a NUL after them when zeroTerm asks (pool storage is
defined-zero, so the terminator is already in place).  For ASCII
this is the octets of u; for a text read off a wire through Chars
it is the wire's bytes again -- which OCTETS (u), the UTF-8 view,
is not: NetCDF's GetAttText read `Â°C' for `°C' through OCTETS

### Chars (VAR pool: POOL ; RO b: SLICE OF BYTE) : UTF RAISES ValueRange

DynStr.Chars's contract: the text whose characters are the octets
of b, ONE CHARACTER PER OCTET (an octet above 127 is the scalar of
that value, two octets in the answer), placed in pool.  For bytes
off a wire or a disk that a parser reads as characters without
saying they are UTF-8 -- HttpServer's request head.  An octet is
always a scalar, so this cannot raise; the signature says what the
checker counts, as DynStr's does
