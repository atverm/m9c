# Hash

SHA-256, fed in pieces; HMAC-SHA-256; PBKDF2-HMAC-SHA256; and a
comparison that takes the same time whatever differs
(docs/library-plan-2.md, item 1).

THE BLOCK FUNCTION IS OPENSSL'S since 2026-10-11 (runtime/
sha256shim.c; a portable C loop on Windows, where m9c links no
OpenSSL).  It was written in M9 until then, every rotation and mask a
call into Bits, and ran at 140 MB/s where OpenSSL ran at 1,984 (the
M4) -- cp-kernel measured the cost, and the ICOS work hashes whole
data objects.  What the M9 version was for stays: a 40 MB response
is hashed as it streams, in pieces, never whole in memory; HMAC and
PBKDF2 are built on it here.

Sha256 is a value: a record the caller holds, Init'ed, Update'd with
any number of slices, and Final'ed once -- a copy of it before Final
is a fork of the stream, which is how PBKDF2 keeps its keyed states
(OpenSSL's SHA256_CTX is a plain struct, so a copy is a fork there
too; EVP's context would not be).  Every digest is answered as fresh
octets in the caller's frame.  Held to Python's hashlib by HashTest:
the FIPS vectors, random lengths across every block boundary, a
million a's, a 64 KB message fed in pieces of every size from 1 to
200, RFC 4231's HMAC cases and the PBKDF2 vectors.

### TYPE Sha256

the C state, 128 octets, 8-aligned:
OpenSSL's SHA256_CTX; opaque here

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

runtime/sha256shim.c: SHA256_CTX through OpenSSL, a portable loop
on Windows.  REENTRANT: every state is the caller's.

### CInit (st: C.MutPtr) [REENTRANT]

_(undocumented)_

### CUpdate (st: C.MutPtr ; p: C.ConstPtr ; n: C.SSizeT) [REENTRANT]

_(undocumented)_

### CFinal (st: C.MutPtr ; out: C.MutPtr) [REENTRANT]

_(undocumented)_
