# ZarrStore

The day's zarr reader, restated as an M9 contract.  Each comment
names the 2026-08-20 bug the construct makes uncompilable.
HTTP-backed zarr v2 store, as the M2 stack's zarrhttp was: C-order,
little-endian numeric dtypes, blosc or raw chunks, missing chunk
means fill_value.  Local-file stores arrive with an OS module.

### TYPE Store

opaque

### TYPE Array

_(documented with the group below)_

### TYPE Dtype

tagged union, CASE total

### EXCEPTION IOError

_(documented with the group below)_

### EXCEPTION FormatError

_(documented with the group below)_

### EXCEPTION HttpStatus

_(documented with the group below)_

### Open (RO url: STR) : SHARED PTR Store RAISES IOError, FormatError

SHARED because every Array retains its Store -- retention is
part of the contract, and plain borrows refuse it (par 4.2).
FormatError is in the signature: the caller that ignored a bad
url today cannot exist -- unhandled RAISES does not compile.

### OpenArray (s: SHARED PTR Store ; RO path: STR) : PTR Array RAISES IOError, FormatError

fill_value validation happens HERE, at open: an integer dtype
with fill NaN raises FormatError now, not Trunc(NaN) later.
[the FPC crash-at-read bug, moved to the contract boundary]

### GetF64 (VAR a: PTR Array ; RO idx: SLICE OF I64) : F64 RAISES IOError

IndexError needs no declaration: it is a checked runtime error,
always on, catchable.  There is no flag that turns it off.
[the -fsoft-check-all "unreachable" bug: unrepresentable]

### GetI64 (VAR a: PTR Array ; RO idx: SLICE OF I64) : I64 RAISES IOError, ValueRange

ValueRange covers BOTH: float element non-finite or beyond I64
[Trunc(NaN) crash], and U64 element above I64 range [the silent
negative-wrap that numpy commits without a warning].

### ReadChunk (VAR a: PTR Array ; RO coords: SLICE OF I64) : SLICE OF BYTE RAISES IOError

READONLY slice into the cache: the caller can read at native
speed but cannot retain it past the next call or mutate it --
the FPC cache-aliasing hazard is a compile error, and the
zero-copy path stays zero-copy.

### Rank (a: PTR Array) : I64

_(documented with the group below)_

### Extent (a: PTR Array ; axis: I64) : I64 RAISES IndexError

_(documented with the group below)_

### HasFill (a: PTR Array) : BOOL

_(documented with the group below)_

### Fill (a: PTR Array) : F64

what THIS array calls a missing value, as a number -- the float
fill for a float dtype, the integer one widened for an integer
dtype.  A caller comparing two copies of a dataset has to ask
per array and not per file: in ICOS's FLUXNET store the floats
fill with 9.969e36 and the quality flags are |u1 filling with
255, and a reader that assumes either one reports 173,899
disagreements that are not there.  Measured, twice: the same
mistake first showed up against the NetCDF copy.

### CloseArray (OWN a: PTR Array)

_(documented with the group below)_

### Close (OWN s: SHARED PTR Store)

OWN: closing consumes the handle; a use after Close is a
compile error, not a crash.

### DecompressCtx (src: C.ConstPtr ; dest: C.MutPtr ; destsize: C.SizeT ; nthreads: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### Decompress (src: C.ConstPtr ; dest: C.MutPtr ; destsize: C.SizeT) : C.Int [SERIAL]

SERIAL: calling this from parbench's Worker threads is a type
error; the compiler forces _ctx or a MONITOR wrapper.
[the blosc global-state trap, moved into the signature]
