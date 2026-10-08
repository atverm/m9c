# Hash

SHA-256, fed in pieces; HMAC-SHA-256; PBKDF2-HMAC-SHA256; and a
comparison that takes the same time whatever differs
(docs/library-plan-2.md, item 1).

WRITTEN IN M9, bit for bit FIPS 180-4, so that a 40 MB response
streaming through HttpServer or a file the zip writer adds is hashed
as it passes and never whole in memory -- the runtime's
`m9_sha256_hex' is a one-shot over a buffer -- and so that it runs
wherever M9 does.  The words are 32-bit patterns held in I64 and
masked after every sum; the rotations are Bits.  Held to Python's
hashlib by HashTest: the FIPS vectors, random lengths across every
block boundary, a million a's, a 64 KB message fed in pieces of
every size from 1 to 200 (the digest must not depend on the
pieces), RFC 4231's HMAC cases and the PBKDF2 vectors.

Sha256 is a value: a record the caller holds, Init'ed, Update'd
with any number of slices, and Final'ed once -- a copy of it before
Final is a fork of the stream, which is how PBKDF2 keeps its keyed
states.  Every digest is answered as fresh octets in the caller's
frame.

### TYPE Sha256

the eight 32-bit words of the state

### TYPE Hmac

after the padded key: the stream goes
through inner, its digest through outer

### CONST DigestLen

_(documented with the group below)_

### CONST BlockLen

_(documented with the group below)_

### Init (VAR h: Sha256)

_(documented with the group below)_

### Update (VAR h: Sha256 ; RO b: SLICE OF BYTE) RAISES ValueRange

_(documented with the group below)_

### Final (VAR h: Sha256) : SLICE OF BYTE RAISES ValueRange

the 32-octet digest of everything Update was given; h is spent

### Sha256Of (RO b: SLICE OF BYTE) : SLICE OF BYTE RAISES ValueRange

the digest of b in one call

### Hex (RO digest: SLICE OF BYTE) : STR RAISES ValueRange

the octets as lower-case hex, two characters each: hashlib's
hexdigest

### HmacInit (VAR m: Hmac ; RO key: SLICE OF BYTE) RAISES ValueRange

_(documented with the group below)_

### HmacUpdate (VAR m: Hmac ; RO b: SLICE OF BYTE) RAISES ValueRange

_(documented with the group below)_

### HmacFinal (VAR m: Hmac) : SLICE OF BYTE RAISES ValueRange

RFC 2104 over SHA-256: a key longer than a block is hashed first

### HmacOf (RO key: SLICE OF BYTE ; RO b: SLICE OF BYTE) : SLICE OF BYTE RAISES ValueRange

_(undocumented)_

### Pbkdf2 (RO password: SLICE OF BYTE ; RO salt: SLICE OF BYTE ; iterations: I64 ; length: I64) : SLICE OF BYTE RAISES ValueRange, Faults.BadArg

RFC 8018's PBKDF2 with HMAC-SHA-256: length octets of key material
(hashlib.pbkdf2_hmac ('sha256', ...)); iterations and length below
1 are BadArg.  A stored password is a salt and this with 600,000
iterations, compared with Equal.  Measured in HashTest

### Equal (RO a: SLICE OF BYTE ; RO b: SLICE OF BYTE) : BOOL

a = b, reading EVERY octet whatever the first difference, so the
time says nothing about where two digests or tokens differ; two
lengths that differ are unequal at once (a length is no secret)
