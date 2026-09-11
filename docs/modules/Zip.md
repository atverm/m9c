# Zip

Reading a member of a ZIP archive as a STREAM.

It exists for one file: SOCAT ships its synthesis product as a
9 GB tab-separated table inside a zip, and the ICOS store builder
walks it once.  Nothing may hold the archive and nothing may hold
the member -- which is the same constraint `Delim` is built for,
one layer down.

WHAT IS SUPPORTED, and everything else is refused BY NAME:
  * stored (method 0) and deflated (method 8) members;
  * ZIP64, which is not optional here -- a member whose
    UNCOMPRESSED size passes 4 GB carries 0xFFFFFFFF in the
    classic fields and its real size in an extra field, and
    SOCAT's is 9 GB;
  * a single-disk archive.
Encryption, multi-disk archives and every other method are refused.

FORWARD ONLY.  A deflate stream has no index, so there is no seek:
`Read` continues from where the last one stopped, and that is the
whole contract.  It is also all a row cursor needs.

`Close` MATTERS.  The z_stream struct lives in this module's pool,
but zlib allocates its own window behind it, and that window is
freed by Close and by nothing else -- not by the pool going away.
A builder that opens one member per run can be forgiven; a loop
that opens thousands cannot.

### TYPE Archive

opaque; lives in a POOL

### TYPE Member

_(undocumented)_

### EXCEPTION Error

_(undocumented)_

### CONST Stored

_(documented with the group below)_

### CONST Deflated

_(documented with the group below)_

### CONST DefaultBlock

the compressed-side read size

### Open (VAR pool: POOL ; RO KEPT path: STR) : PTR Archive IN pool RAISES Error, Io.IOError, ValueRange

reads the central directory, nothing else.

### Count (a: PTR Archive) : I64

_(documented with the group below)_

### NameAt (VAR pool: POOL ; a: PTR Archive ; i: I64) : STR RAISES IndexError

the member's name as stored.  ZIP names are bytes; this decodes
UTF-8 when the entry's flag bit 11 says so and Latin-1 when it
does not, which is what the format actually means and what
python's zipfile does.

### SizeAt (a: PTR Archive ; i: I64) : I64 RAISES IndexError

the UNCOMPRESSED size.

### MethodAt (a: PTR Archive ; i: I64) : I64 RAISES IndexError

_(documented with the group below)_

### Find (VAR pool: POOL ; a: PTR Archive ; RO name: STR) : I64 RAISES ValueRange, IndexError

the index of that member, or -1.

### OpenMember (VAR pool: POOL ; KEPT a: PTR Archive ; i: I64 ; block: I64) : PTR Member IN pool RAISES Error, Io.IOError, ValueRange, IndexError

`block` is the COMPRESSED-side read size; 0 for DefaultBlock.

### Read (VAR m: PTR Member ; VAR dst: SLICE OF BYTE) : I64 RAISES Error, Io.IOError, ValueRange

fills `dst` as far as it can, answering how many bytes; 0 means
the member is finished.  A short answer is NOT the end -- inflate
stops at its own boundaries -- so a caller wanting a full buffer
loops until 0.

### Close (VAR m: PTR Member)

_(undocumented)_

### InflSize () : C.SSizeT [REENTRANT]

_(undocumented)_

### InflInit (zs: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### InflStep (zs: C.MutPtr ; src: C.ConstPtr ; nsrc: C.SSizeT ; dst: C.MutPtr ; ndst: C.SSizeT ; out: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### InflEnd (zs: C.MutPtr) [REENTRANT]

_(undocumented)_
