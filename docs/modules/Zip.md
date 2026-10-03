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

THE INFLATE IS WRITTEN HERE, IN M9 (2026-10-02; Alex's decision).
Until then the stream went to zlib through a shim, and so a
program that read a member needed zlib on its own link line: the
compiler supplies the runtime and no other library.  Now a
program that imports Zip links as any program does, on every
platform.  The decoder is RFC 1951's, table-driven.  It is SLOWER
than zlib, measured on a 92 MB table that deflate takes to a
fifth: a member read as a stream at 235 MB/s where zlib gave 500
(0.46), a gzip file with its CRC at 215 MB/s where zlib gave 305
(0.7).  What is left is the price of an index checked at every
byte copied; zlib copies a run with one memcpy.

`Close` frees nothing any more -- the decoder's window is in the
pool the member lives in and goes with it -- and is kept because
callers call it: it marks the member finished.

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

### NameAt (a: PTR Archive ; i: I64) : STR RAISES IndexError

the member's name as stored.  ZIP names are bytes; this decodes
UTF-8 when the entry's flag bit 11 says so and Latin-1 when it
does not, which is what the format actually means and what
python's zipfile does.

### SizeAt (a: PTR Archive ; i: I64) : I64 RAISES IndexError

the UNCOMPRESSED size.

### MethodAt (a: PTR Archive ; i: I64) : I64 RAISES IndexError

_(documented with the group below)_

### Find (a: PTR Archive ; RO name: STR) : I64 RAISES ValueRange, IndexError

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

### Gunzip (VAR pool: POOL ; RO path: STR) : SLICE OF BYTE RAISES Error, Io.IOError, ValueRange

the uncompressed bytes of the file at path

### GunzipBytes (VAR pool: POOL ; RO data: SLICE OF BYTE) : SLICE OF BYTE RAISES Error, ValueRange

the same of bytes already held, an HTTP body sent with
Content-Encoding: gzip for one

### Deflate (VAR pool: POOL ; RO data: SLICE OF BYTE) : SLICE OF BYTE RAISES ValueRange

the bare deflate stream (RFC 1951), no header and no checksum

### Compress (VAR pool: POOL ; RO data: SLICE OF BYTE) : SLICE OF BYTE RAISES ValueRange

the zlib wrapping (RFC 1950): two bytes of header, the stream,
its Adler-32.  Python's zlib.decompress reads it; a PNG's image
data is this.

### Decompress (VAR pool: POOL ; RO data: SLICE OF BYTE) : SLICE OF BYTE RAISES Error, ValueRange

what Compress, or any zlib, wrapped: Python's zlib.decompress.
Error by name for what does not begin as zlib, asks for a preset
dictionary, is damaged or stops early, has an Adler-32 its bytes
do not bear out, or goes on after it.

### Gzip (VAR pool: POOL ; RO data: SLICE OF BYTE) : SLICE OF BYTE RAISES ValueRange

a gzip file's bytes (RFC 1952): one member, no name, no time --
so the same bytes in give the same bytes out -- with its CRC-32
and length.  GunzipBytes undoes it.

### Crc32 (RO b: SLICE OF BYTE) : I64 RAISES ValueRange

the CRC-32 of gzip, zip and PNG (zlib.crc32), 0 .. 4294967295

### Adler32 (RO b: SLICE OF BYTE) : I64

the checksum of the zlib wrapping (zlib.adler32)
