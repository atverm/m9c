# NetCDF

NetCDF, the classic and netCDF-4 data model, read and write.

Written for the FLEXPART port (port/flexpart/), whose input and
output both go through this library: 41 nf90_get_var, 113
nf90_put_var and 228 nf90_put_att in the model's own source.  The
surface below is what those calls need and nothing else -- groups,
compound types, compression settings and the parallel API are not
here, and will arrive when a caller asks rather than in case one
does.

WHAT THE BINDING FIXES ABOUT THE C API.

Every C entry point answers an int status that a caller may
ignore, and the model ignores it 679 times behind a `nf90_err`
helper that halts.  Here a bad status is an Error with the failing
operation and the library's own message in it, and a halt is not
one of the outcomes -- a reader that halts cannot be tested (the
museum HALT piece).

Dimensions and shapes cross as I64.  The C API says size_t, which
is unsigned, so a negative extent is not a size but a very large
one; the conversion here raises rather than passing it on.

THREADS.  Every procedure in the foreign unit is [SERIAL].  The
netCDF-4 path goes through HDF5, which serialises on a global lock
and is only thread-safe when built for it, and the classic path
keeps per-file state in library globals.  Declaring REENTRANT
because it "usually works" is exactly the blosc museum piece, so
this says SERIAL and the checker refuses to call it from a THREAD
root.  A caller that wants concurrency needs one process per file
or a MONITOR.

### TYPE File

opaque; an ncid and its name

### EXCEPTION Error

op is what was attempted, detail is the library's own message
(nc_strerror), status is the number.  All three, because a
reader who has only one of them goes looking for the other
two.

### EXCEPTION SizeError

nc_type, from netcdf.h.  Named here rather than passed as bare
integers: a variable declared with the wrong type code is a bug
that reads back as garbage, and the museum has that shape
already (the 16-byte stride over 8-byte doubles).

### CONST TypeByte

_(documented with the group below)_

### CONST TypeChar

_(documented with the group below)_

### CONST TypeShort

_(documented with the group below)_

### CONST TypeInt

_(documented with the group below)_

### CONST TypeFloat

_(documented with the group below)_

### CONST TypeDouble

_(documented with the group below)_

### CONST TypeUByte

_(documented with the group below)_

### CONST TypeInt64

_(documented with the group below)_

### CONST Unlimited

the extent NC_UNLIMITED means

### Open (VAR pool: POOL ; RO path: STR) : PTR File IN pool RAISES Error, ValueRange

read-only.  The pool owns the handle; Close releases the file
but the record dies with the pool, which is why Close takes a
VAR and not an OWN: there is nothing here to move.

### OpenRW (VAR pool: POOL ; RO path: STR) : PTR File IN pool RAISES Error, ValueRange

read-write on an EXISTING file: what a restarted run does to
the output it left half-written -- inquire the variables back
and continue appending records.  Everything Put* works; Def*
would need redef mode and is not supported through this.

### Create (VAR pool: POOL ; RO path: STR ; clobber: BOOL) : PTR File IN pool RAISES Error, ValueRange

the CLASSIC format.  Its unlimited dimension must be a
variable's OUTERMOST one, which is a real constraint on how a
file may be laid out -- see Create4.

### Create4 (VAR pool: POOL ; RO path: STR ; clobber: BOOL) : PTR File IN pool RAISES Error, ValueRange

netCDF-4 (HDF5 underneath).

Two things it allows that the classic format does not, both of
which a gridded time series wants: the unlimited dimension may
sit ANYWHERE in a variable's shape, so the axis order can follow
how the data is read rather than how the format insists; and
more than one unlimited dimension.  Classic netCDF answers
`NC_UNLIMITED in the wrong index` otherwise, which is how this
was found.

### Close (VAR f: PTR File) RAISES Error

flushes and releases the underlying handle.  It RAISES, and the
raise matters: netCDF buffers, so a write error can surface
HERE and nowhere earlier, and a Close whose result is discarded
is how a truncated file gets reported as a successful run.

  f -- VAR, and left unusable afterwards.  The record itself
       dies with the pool, so this is a release and not a move;
       there is nothing here to OWN.

### VarId (f: PTR File ; RO name: STR) : I64 RAISES Error, ValueRange

_(documented with the group below)_

### DimId (f: PTR File ; RO name: STR) : I64 RAISES Error, ValueRange

_(documented with the group below)_

### DimLen (f: PTR File ; dimid: I64) : I64 RAISES Error, ValueRange

_(documented with the group below)_

### DimCount (f: PTR File) : I64 RAISES Error, ValueRange

how many dimensions the file declares

### DimName (VAR pool: POOL ; f: PTR File ; dimid: I64) : STR RAISES Error, ValueRange, IndexError, Overflow

the name of one dimension; reademissions-style readers discover
the longitude/latitude/time axes by NAME rather than assuming an
order

### DimLenOf (f: PTR File ; RO name: STR) : I64 RAISES Error, ValueRange

the extent of a dimension by name, which is what a reader that
does not already know the file wants to ask

### VarRank (f: PTR File ; varid: I64) : I64 RAISES Error, ValueRange

_(documented with the group below)_

### VarShape (VAR pool: POOL ; f: PTR File ; varid: I64) : SLICE OF I64 RAISES Error, ValueRange

the extents, outermost axis first -- C order, which is also
M9's: the last axis is contiguous in both.  A NetCDF file and a
GRID agree about layout without anybody transposing anything,
which is the one place row-major pays for itself twice.

### GetF64 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF F64) RAISES Error, SizeError, ValueRange

one hyperslab into a flat slice.  LEN (out) must be the product
of count, and is checked: the C call would otherwise write past
the end of a buffer the caller sized wrongly, which is the whole
class of bug this language exists to remove.

### GetF32 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF F32) RAISES Error, SizeError, ValueRange

_(undocumented)_

### GetI64 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF I64) RAISES Error, SizeError, ValueRange

the same hyperslab read at the other two widths, with the same
LEN (out) = product-of-count check.  netCDF CONVERTS on the way
out, so the file's own type need not be the one asked for --
which is convenient and is also how a float file quietly loses
precision into an F32 buffer.  The width is the caller's
decision and is written down at the call site, which is the
most this layer can do about it.

### ReadGrid2 (VAR pool: POOL ; f: PTR File ; RO name: STR) : GRID 2 OF F64 RAISES Error, SizeError, ValueRange

_(documented with the group below)_

### ReadGrid3 (VAR pool: POOL ; f: PTR File ; RO name: STR) : GRID 3 OF F64 RAISES Error, SizeError, ValueRange

a whole variable, shape and all, as a GRID.  These exist because
a GRID can today only come from NEW or VIEW: there is no way to
say "this slice, seen as 3 axes", so a reader that wants indexed
access must allocate and copy.  The copy is one pass and is
noted in the port ledger as the cost of a missing
`GRID (s, n0, n1, n2)` view form.

### GetAttF64 (f: PTR File ; varid: I64 ; RO name: STR) : F64 RAISES Error, ValueRange

_(undocumented)_

### GetAttStr (VAR pool: POOL ; f: PTR File ; varid: I64 ; RO name: STR) : STR RAISES Error, ValueRange

_(undocumented)_

### HasVar (f: PTR File ; RO name: STR) : BOOL RAISES ValueRange

asks whether a variable exists without making its absence an
error: a reader choosing between conventions needs the question,
not the diagnosis

### HasAtt (f: PTR File ; varid: I64 ; RO name: STR) : BOOL RAISES ValueRange

_(documented with the group below)_

### VarCount (f: PTR File) : I64 RAISES Error

_(documented with the group below)_

### VarName (VAR pool: POOL ; f: PTR File ; varid: I64) : STR RAISES Error, ValueRange

_(documented with the group below)_

### VarType (f: PTR File ; varid: I64) : I64 RAISES Error

_(documented with the group below)_

### VarDims (VAR pool: POOL ; f: PTR File ; varid: I64) : SLICE OF I64 RAISES Error, ValueRange

enumeration: how many variables, their names, their nc_type
(against the Type* constants) and their dimension IDS in
order.  Added for Frame.m9, which walks a file it did not
write.

### GetI32 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF I32) RAISES Error, SizeError, ValueRange

_(undocumented)_

### GetI16 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF I16) RAISES Error, SizeError, ValueRange

_(undocumented)_

### GetBytes (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; out: SLICE OF BYTE) RAISES Error, SizeError, ValueRange

_(undocumented)_

### DefDim (f: PTR File ; RO name: STR ; extent: I64) : I64 RAISES Error, ValueRange

declares a dimension and answers its id, which is what DefVar
takes.

  extent -- the length.  Zero declares the UNLIMITED dimension,
            which grows as records are written; every other
            axis is fixed at this value.  A negative extent is
            an Error rather than an enormous size_t.

### DefVar (f: PTR File ; RO name: STR ; nctype: I64 ; RO dims: SLICE OF I64) : I64 RAISES Error, ValueRange

declares a variable and answers its id.

nctype -- one of the NcF64/NcF32/NcI64 constants below, the
          type as STORED.  Get and Put convert, so this is
          what the file costs on disk, not what callers must
          use.
dims   -- dimension ids from DefDim, OUTERMOST FIRST, C
          order.  An empty slice declares a scalar.  This is
          the same order VarShape answers in and the same
          order a GRID indexes in, so nothing transposes.

### PutAttStr (f: PTR File ; varid: I64 ; RO name: STR ; RO value: STR) RAISES Error, ValueRange

_(documented with the group below)_

### PutAttF64 (f: PTR File ; varid: I64 ; RO name: STR ; value: F64) RAISES Error, ValueRange

one attribute, text or number.

  varid -- a variable's id, or Global (below) for an attribute
           on the file itself.  Global is -1 and is spelled out
           rather than passed as a bare -1, because a magic
           number in an argument list is a comment nobody
           checks.

ValueRange is the CHAR/octet boundary: netCDF text attributes
are bytes, so a scalar past 255 raises here rather than
reaching the file as mojibake.

### EndDef (f: PTR File) RAISES Error

leaves define mode and commits the header.  Nothing may be
declared afterwards and nothing may be written before.

### PutF64 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO data: SLICE OF F64) RAISES Error, SizeError, ValueRange

_(undocumented)_

### FillF32 (f: PTR File ; varid: I64 ; fill: F32) RAISES Error, ValueRange

the value an UNWRITTEN cell reads back as.  netCDF's default is
9.97e36, which makes skipping a write a silent lie; set to the
quantity's own zero, an unwritten hyperslab IS zero and a writer
may honestly skip regions nothing touched.  Must be called in
define mode, like Deflate.

### Deflate (f: PTR File ; varid: I64 ; level: I64) RAISES Error, ValueRange

compress a variable, netCDF-4 only, between EndDef and the first
write -- in practice immediately after DefVar.

WHY IT IS NOT OPTIONAL FOR A GRIDDED FIELD.  Measured on a
FLEXPART-M9 footprint: 24 releases x 23 times x 6 levels x 90 x
140 floats is 167 MB written plainly and 0.9 MB deflated,
because a footprint is mostly zeros.  A file nobody can store is
not an output format.  `shuffle` is on: it groups the bytes of
equal significance together, which is what makes a float field
compress at all.

### Chunking (f: PTR File ; varid: I64 ; RO sizes: SLICE OF I64) RAISES Error, ValueRange

the chunk shape, netCDF-4 only.  Compression works on a chunk at
a time, and so does reading: a chunk that spans the axes a
reader slices along is read whole for one value.  A map for one
release at one time wants (1,1,1,1,nz,ny,nx), not a chunk that
cuts across time.

### PutChars (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO text: STR) RAISES Error, SizeError, ValueRange

one hyperslab of TEXT out, for a char variable.

CF's labelled axes (6.1) are char arrays -- a `species_name(
species, strlen)` beside a species dimension is what lets a
reader slice across species instead of parsing variable names --
and there was no way to write one until this.  Short text is
PADDED WITH NUL to the count, because a char variable's trailing
bytes are whatever was there otherwise, and netCDF does not do it
for you.

### PutI64 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO v: SLICE OF I64) RAISES Error, SizeError, ValueRange

_(undocumented)_

### PutI32 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO v: SLICE OF I32) RAISES Error, SizeError, ValueRange

_(undocumented)_

### PutI16 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO v: SLICE OF I16) RAISES Error, SizeError, ValueRange

_(undocumented)_

### PutBytes (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO v: SLICE OF BYTE) RAISES Error, SizeError, ValueRange

_(undocumented)_

### FillF64 (f: PTR File ; varid: I64 ; fill: F64) RAISES Error, ValueRange

_(undocumented)_

### FillI64 (f: PTR File ; varid: I64 ; fill: I64) RAISES Error, ValueRange

_(undocumented)_

### FillI32 (f: PTR File ; varid: I64 ; fill: I32) RAISES Error, ValueRange

_(undocumented)_

### FillI16 (f: PTR File ; varid: I64 ; fill: I16) RAISES Error, ValueRange

_(undocumented)_

### FillByte (f: PTR File ; varid: I64 ; fill: BYTE) RAISES Error, ValueRange

_(undocumented)_

### GetChars (VAR pool: POOL ; f: PTR File ; varid: I64 ; n, width: I64) : SLICE OF STR RAISES Error, SizeError, ValueRange

the reverse of PutChars: an n x width char matrix, each row
answered as a STR with trailing NULs and blanks removed

### PutF32 (f: PTR File ; varid: I64 ; RO start: SLICE OF I64 ; RO count: SLICE OF I64 ; RO data: SLICE OF F32) RAISES Error, SizeError, ValueRange

one hyperslab out, the mirror of GetF64/GetF32.

start -- the corner, one index per axis, outermost first.
count -- the extent along each axis from that corner.
data  -- LEN (data) must be the PRODUCT of count, and is
         checked: SizeError rather than letting the C call
         read past the end of a buffer the caller sized
         wrongly.  Same rule as the readers, stated on both
         sides because getting it wrong writes garbage into a
         file instead of merely reading it.

### CONST Global

NC_GLOBAL, for file attributes

libnetcdf, verbatim.  Every one is [SERIAL]: netCDF-4 goes through
HDF5's global lock and the classic path keeps per-file state in
library globals.  The library's own documentation says it is not
thread-safe unless built to be, and "usually works" is how the
blosc museum piece was written.

### NcOpen (path: C.ConstPtr ; mode: C.Int ; ncidp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcCreate (path: C.ConstPtr ; mode: C.Int ; ncidp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcClose (ncid: C.Int) : C.Int [SERIAL]

_(undocumented)_

### NcStrError (status: C.Int) : C.ConstPtr [SERIAL]

_(undocumented)_

### NcInqVarId (ncid: C.Int ; name: C.ConstPtr ; varidp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqDimId (ncid: C.Int ; name: C.ConstPtr ; dimidp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqDimLen (ncid: C.Int ; dimid: C.Int ; lenp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqNDims (ncid: C.Int ; ndims: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqDimName (ncid: C.Int ; dimid: C.Int ; name: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqVarNDims (ncid: C.Int ; varid: C.Int ; ndimsp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqVarDimIds (ncid: C.Int ; varid: C.Int ; dimids: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraDouble (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; ip: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraFloat (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; ip: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraLong (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; ip: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetAttDouble (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; value: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqAttLen (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; lenp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetAttText (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; value: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcDefDim (ncid: C.Int ; name: C.ConstPtr ; len: C.SizeT ; idp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcDefVar (ncid: C.Int ; name: C.ConstPtr ; xtype: C.Int ; ndims: C.Int ; dimids: C.ConstPtr ; varidp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutAttText (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; len: C.SizeT ; op: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutAttDouble (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; xtype: C.Int ; len: C.SizeT ; op: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcEndDef (ncid: C.Int) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraDouble (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; op: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraFloat (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; op: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcDeflate (ncid: C.Int ; varid: C.Int ; shuffle: C.Int ; deflate: C.Int ; level: C.Int) : C.Int [SERIAL]

_(undocumented)_

### NcInqNVars (ncid: C.Int ; nvars: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqVarName (ncid: C.Int ; varid: C.Int ; name: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqVarType (ncid: C.Int ; varid: C.Int ; tp: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcInqAtt (ncid: C.Int ; varid: C.Int ; name: C.ConstPtr ; tp: C.MutPtr ; len: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraInt (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraShort (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraUByte (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcGetVaraText (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.MutPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraLong (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraInt (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraShort (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraUByte (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; v: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcDefVarFill (ncid: C.Int ; varid: C.Int ; noFill: C.Int ; fill: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcChunking (ncid: C.Int ; varid: C.Int ; storage: C.Int ; sizes: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### NcPutVaraText (ncid: C.Int ; varid: C.Int ; start: C.ConstPtr ; count: C.ConstPtr ; op: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### CLen (s: C.ConstPtr) : C.SSizeT [REENTRANT]

the runtime's shim, not strlen itself: C.ConstPtr is
`const void *` and string.h has already declared strlen with
`const char *`, so the foreign declaration would collide

### CCopy (d: C.MutPtr ; s: C.ConstPtr ; n: C.SizeT) : C.MutPtr [REENTRANT]

_(undocumented)_
