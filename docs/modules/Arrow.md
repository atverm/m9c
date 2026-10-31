# Arrow

Arrow writes an Apache Arrow IPC STREAM.

The stream is one schema message, one record batch and one
end-of-stream marker: the shape `pyarrow.ipc.open_stream` reads and
the shape a service answers `format=arrow` with.  Arrow writes a
SUBSET deliberately.  The parts outside it are refused BY NAME
rather than half-written, because a columnar file that decodes into
the wrong cells is a numbers-shaped lie.  That is Parquet.m9's
rule, and the reason pyarrow is the oracle in
runtime/test/arrow_driver.c.

IN THE SUBSET: flat schemas; int8/16/32/64, float32/64, UTF-8
strings, and timestamps in nanoseconds; one record batch; schema
custom_metadata.  The body is uncompressed (Stream), or every body
buffer is compressed with ZSTD (StreamCodec).  Then the record
batch's BodyCompression says so, and each buffer is its
uncompressed length as 8 little-endian bytes and then one zstd
frame.  A buffer zstd would not make smaller is the length -1 and
the bytes as they were, which the format allows for exactly that.
An empty buffer stays empty.  libzstd is the system's (LINK below),
as Parquet's ZSTD pages are; lz4, the format's other codec, is not
written.

OUT OF THE SUBSET, and refused: nulls.  Every column here is
written with an EMPTY validity buffer and a null_count of zero,
which is what a numpy array with no mask becomes, and it is what
these callers have.  A column that needs nulls must say so, and
this module would have to grow a bitmap rather than guess.  The
missing-value convention in the data (NaN, a sentinel) is the
caller's, unchanged, exactly as Parquet.m9 leaves it.

THE FORMAT, so a reader of this file need not have the spec open.
A stream is a sequence of encapsulated messages:

  <0xFFFFFFFF> <int32 metadata length> <flatbuffer> <pad to 8> [body]

and ends with a length of zero.  The metadata length COUNTS its own
padding, so every body starts 8-aligned.  Inside the body each
buffer is padded to 8 as well, and the record batch names every
buffer by (offset, length) so a reader never has to guess.  The
flatbuffer field numbers are the interesting part and they are
written down at each table below; they were read off a stream
pyarrow produced rather than remembered.

### TYPE Table

opaque; lives in a POOL

### CONST TyI8

_(documented with the group below)_

### CONST TyI16

_(documented with the group below)_

### CONST TyI32

_(documented with the group below)_

### CONST TyI64

_(documented with the group below)_

### CONST TyF32

_(documented with the group below)_

### CONST TyF64

_(documented with the group below)_

### CONST TyStr

_(documented with the group below)_

### CONST TyTsNs

timestamp, nanoseconds,
NO timezone: naive, as a
numpy datetime64 lands

### CONST CodecNone

_(documented with the group below)_

### CONST CodecZstd

StreamCodec's codec.  The
numbers are this module's:
the format spells LZ4_FRAME
0 and ZSTD 1, and 0 here
must mean "nothing asked"

### New (VAR pool: POOL ; rows: I64) : PTR Table IN pool

New answers an empty table of `rows` rows.  Columns are added in
order, and that is the order the schema and the batch carry.

### Meta (VAR t: PTR Table ; RO KEPT key: STR ; RO KEPT value: STR)

Meta adds a schema custom_metadata entry, where a data passport
rides.  KEPT: the table holds VIEWS of the caller's strings, as
HttpServer.AddRoute holds its own, so they must outlive it.

### AddInt (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; ty: I64 ; RO KEPT v: SLICE OF I64) RAISES Faults.BadArg

AddInt adds an integer or timestamp column, values carried as I64
and narrowed to the declared width.  A value that will not fit
RAISES rather than wrapping: the width is the wire's, and a
silent truncation here is a wrong number in someone's dataframe.

### AddF32 (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF F32) RAISES Faults.BadArg

_(undocumented)_

### AddF64 (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF F64) RAISES Faults.BadArg

_(undocumented)_

### AddStr (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF STR) RAISES Faults.BadArg, ValueRange

AddStr puts UTF-8 on the wire, encoded here from the caller's
CHARs.

### Stream (VAR pool: POOL ; t: PTR Table) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange

Stream answers the whole stream, in pool.

### StreamCodec (VAR pool: POOL ; t: PTR Table ; codec, level: I64) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange

StreamCodec answers the same stream with its body buffers
compressed.  CodecNone is Stream's bytes exactly, and CodecZstd
is libzstd at `level' (1 is pyarrow's own default for ZSTD, 3 is
libzstd's).  Another codec is BadArg by name.  The schema and
every cell read back the same either way; only the wire
shrinks.

### NBytes (t: PTR Table) : I64

NBytes answers what pyarrow's `table.nbytes` answers for this
table, which is NOT the stream length.  It is Arrow's in-memory
buffer accounting, and a caller reporting a size in a passport
must use this rather than measuring the wire.  A string column
counts 4n + data, NOT 4(n+1): the offsets buffer is one longer on
the wire than nbytes admits.  A column with no nulls carries no
validity bytes at all.  Both were measured against pyarrow, and
the first cost an 8-byte passport error on two string columns
the last time this was written.

### TYPE Reader

opaque; lives in a POOL

### Open (VAR pool: POOL ; RO KEPT src: SLICE OF BYTE) : PTR Reader IN pool RAISES Faults.BadArg, ValueRange

Open reads the schema: the stream's first message.  `src' is the
whole stream, read where it lies until the last batch is read.

### NFields (r: PTR Reader) : I64

_(documented with the group below)_

### FieldName (r: PTR Reader ; i: I64) : STR RAISES IndexError

_(documented with the group below)_

### FieldType (r: PTR Reader ; i: I64) : I64 RAISES IndexError

FieldType answers one of the Ty constants above.

### FieldTz (r: PTR Reader ; i: I64) : STR RAISES IndexError

FieldTz answers a timestamp column's time zone as the schema
spells it, 'UTC' or '+01:00', or '' for a naive timestamp and for
any other column.

### MetaOf (r: PTR Reader ; RO key: STR) : STR

MetaOf answers the schema's custom_metadata value for key, ''
when absent.

### Next (VAR r: PTR Reader) : BOOL RAISES Faults.BadArg, ValueRange

Next reads the next record batch, and answers FALSE at the end of
the stream (its zero-length marker, or the bytes running out
where a message would start).

### Rows (r: PTR Reader) : I64

Rows answers the current batch's row count; 0 before the first
Next.

### Nulls (r: PTR Reader ; i: I64) : I64 RAISES IndexError

Nulls answers column i's null count in the current batch.

### IsNull (r: PTR Reader ; i, row: I64) : BOOL RAISES IndexError

_(documented with the group below)_

### GetF64 (VAR pool: POOL ; r: PTR Reader ; i: I64) : SLICE OF F64 RAISES Faults.BadArg, IndexError

GetF64 answers a float32 or float64 column of the current batch,
float32 widened exactly; a null is NaN.  Any other column is
BadArg.

### GetI64 (VAR pool: POOL ; r: PTR Reader ; i: I64) : SLICE OF I64 RAISES Faults.BadArg, IndexError

GetI64 answers an integer or timestamp column (nanoseconds since
the epoch); a null is 0, so ask IsNull.  Any other column is
BadArg.

### GetStr (VAR pool: POOL ; r: PTR Reader ; i, row: I64) : STR RAISES Faults.BadArg, IndexError, ValueRange

GetStr answers one cell of a string column, decoded from UTF-8
(ValueRange for bytes that are not UTF-8); a null is ''.  Any
other column is BadArg.

carrowz binds libzstd's one-shot compressor, as Parquet's czstd
binds it: each call makes and frees its own context, so any number
of threads may call it at once.  An error is a size_t near 2 ** 64,
which I64 () refuses with ValueRange.  carrowz is its own unit, not
Parquet's, so that Arrow does not import Parquet and a program
linking both has two units of distinct names over the same two
symbols.

### ZstdCompress (dst: C.MutPtr ; cap: C.SizeT ; src: C.ConstPtr ; n: C.SizeT ; level: C.Int) : C.SizeT [REENTRANT]

_(undocumented)_

### ZstdBound (n: C.SizeT) : C.SizeT [REENTRANT]

_(undocumented)_

### ZstdDecompress (dst: C.MutPtr ; cap: C.SizeT ; src: C.ConstPtr ; n: C.SizeT) : C.SizeT [REENTRANT]

_(undocumented)_
