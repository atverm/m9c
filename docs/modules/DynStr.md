# DynStr

DynStr holds growable UTF-8 text.  It is DynUtf's body under
DynStr's name since STR became the UTF-8 type (2026-10-31,
docs/utf8-stage4-plan.md decision 4); DynUtf stays beside it, the
same builder, for programs that still name it.  The CHAR builder
that had the name is gone (docs/utfbuilder-plan.md).

The buffer holds octets, a quarter of the CHAR builder's for ASCII,
and only whole UTF-8 sequences.  Every writer below appends a UTF, one
encoded scalar or ASCII digits.  Text comes back as a COPY (View,
ViewIn), because a UTF view of octets this module still writes
would be the hole UTF (b) copies against.  The octets come back as
a read-only view (Octets), for what leaves as octets anyway.

### TYPE DString

opaque; lives in a POOL

### New (VAR pool: POOL) : PTR DString IN pool

New answers an empty text, sixteen octets of room, owned by
pool.  The text and every buffer it outgrows are carved there.

### Append (VAR d: PTR DString ; RO s: UTF)

Append puts the octets of s onto the end, growing the buffer
when it is full.
  d -- VAR because growing REPLACES the buffer; an Octets view
       taken before still reads the old octets.
  s -- copied; appending d's own View to d is safe, it is a copy

### AppendChar (VAR d: PTR DString ; ch: CHAR)

AppendChar appends one scalar, encoded: one to four octets.

### AppendI64 (VAR d: PTR DString ; v: I64)

AppendI64 appends the decimal text of v, a minus sign first when
negative.  MIN (I64) is included.

### AppendStr (VAR d: PTR DString ; RO s: STR)

AppendStr is Append since STR is the UTF-8 type.  It was the
bridge from the CHAR builder's STR, and goes with the twins.

### BLen (d: PTR DString) : I64

BLen answers the octets written so far, never the room, O(1).

### View (d: PTR DString) : UTF

View answers the text so far, COPIED into the caller's frame,
O(n).  The octets are validated as the copy is made.  Nothing
writes a part of a character, so they cannot fail.  Were they
to, the answer is an IndexError, never a wrong text.

### ViewIn (VAR pool: POOL ; d: PTR DString) : UTF

ViewIn is View with the copy made in pool, for text stored into
a structure that outlives the frame.

### Octets (d: PTR DString) : SLICE OF BYTE

Octets answers the octets so far, a read-only VIEW of the
buffer, O(1): for a file, a hash or a socket.  The view is valid
until the next append that grows it.

### Equal (d: PTR DString ; RO s: UTF) : BOOL

Equal answers TRUE when the text so far equals s, octet by
octet, with no copy.

### Bytes (VAR pool: POOL ; RO u: UTF ; zeroTerm: BOOL) : SLICE OF BYTE RAISES ValueRange

Bytes keeps DynStr.Bytes's contract, the inverse of Chars: ONE
OCTET PER CHARACTER, a character past 255 refused as ValueRange,
in pool, with a NUL after them when zeroTerm asks.  Pool storage
is defined-zero, so the terminator is already in place.  For
ASCII this is the octets of u.  For a text read off a wire
through Chars it is the wire's bytes again.  OCTETS (u), the
UTF-8 view, is not: NetCDF's GetAttText read `Â°C' for `°C'
through OCTETS.

### Chars (VAR pool: POOL ; RO b: SLICE OF BYTE) : UTF RAISES ValueRange

Chars keeps DynStr.Chars's contract.  It answers the text whose
characters are the octets of b, ONE CHARACTER PER OCTET, placed
in pool.  An octet above 127 is the scalar of that value, two
octets in the answer.  Chars serves bytes off a wire or a disk
that a parser reads as characters without saying they are UTF-8,
such as HttpServer's request head.  An octet is always a scalar,
so this cannot raise.  The signature says what the checker
counts, as DynStr's does.

### Wire (VAR pool: POOL ; RO u: UTF ; zeroTerm: BOOL) : SLICE OF BYTE RAISES IndexError

Wire answers the UTF-8 octets of u, copied into pool, with a NUL
after them when zeroTerm asks.  It is what text becomes on a
socket, in a file name or at the C boundary (Alex, 2026-10-31).
Every character has its octets, so nothing is refused.

### Decoded (VAR pool: POOL ; RO b: SLICE OF BYTE) : UTF RAISES ValueRange

Decoded answers the text that the octets b carry, in pool: b
itself when it is valid UTF-8, else one character per octet, as
Chars reads it.  So a peer that sends Latin-1 still reads, and
Wire gives UTF-8 back.  The signature names Chars's ValueRange,
which cannot fire.
