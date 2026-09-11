# Arrow

An Apache Arrow IPC STREAM, written.

One schema message, one record batch, one end-of-stream marker --
the shape `pyarrow.ipc.open_stream` reads and the shape a service
answers `format=arrow` with.  Deliberately a SUBSET, and the parts
outside it are refused BY NAME rather than half-written, because a
columnar file that decodes into the wrong cells is a numbers-shaped
lie: Parquet.m9's rule, and the reason pyarrow is the oracle in
runtime/test/arrow_driver.c.

IN THE SUBSET: flat schemas; int8/16/32/64, float32/64, UTF-8
strings, and timestamps in nanoseconds; one record batch; schema
custom_metadata.  UNCOMPRESSED -- Arrow's per-buffer compression
would need a zstd or lz4 binding, and a reader accepts an
uncompressed stream from a writer that compresses, so the cost is
bytes on the wire and nothing else.

OUT OF THE SUBSET, and refused: nulls.  Every column here is
written with an EMPTY validity buffer and a null_count of zero,
which is what a numpy array with no mask becomes, and it is what
these callers have.  A column that needs nulls must say so, and
this module would have to grow a bitmap rather than guess.  The
missing-value convention in the data -- NaN, a sentinel -- is the
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

### EXCEPTION Bad

what this writer will not do, named: a column length that
disagrees with the table's, a type outside the subset, a value
that will not fit the width it was asked for, or metadata past
the builder's room.  Never a silent narrowing.

### New (VAR pool: POOL ; rows: I64) : PTR Table IN pool

an empty table of `rows` rows.  Columns are added in order and
that is the order the schema and the batch carry.

### Meta (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT key: STR ; RO KEPT value: STR)

a schema custom_metadata entry -- where a data passport rides.
KEPT: the table holds VIEWS of the caller's strings, as
HttpServer.AddRoute holds its own, so they must outlive it.

### AddInt (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; ty: I64 ; RO KEPT v: SLICE OF I64) RAISES Bad

an integer or timestamp column, values carried as I64 and
narrowed to the declared width.  A value that will not fit
RAISES rather than wrapping: the width is the wire's, and a
silent truncation here is a wrong number in someone's dataframe.

### AddF32 (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF F32) RAISES Bad

_(undocumented)_

### AddF64 (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF F64) RAISES Bad

_(undocumented)_

### AddStr (VAR pool: POOL ; VAR t: PTR Table ; RO KEPT name: STR ; RO KEPT v: SLICE OF STR) RAISES Bad, ValueRange

UTF-8 on the wire, encoded here from the caller's CHARs.

### Stream (VAR pool: POOL ; t: PTR Table) : SLICE OF BYTE RAISES Bad, ValueRange

the whole stream, in pool.

### NBytes (t: PTR Table) : I64

what pyarrow's `table.nbytes` answers for this table, which is
NOT the stream length: it is Arrow's in-memory buffer
accounting, and a caller reporting a size in a passport must use
this rather than measuring the wire.  A string column counts
4n + data, NOT 4(n+1) -- the offsets buffer is one longer on the
wire than nbytes admits -- and a column with no nulls carries no
validity bytes at all.  Both were measured against pyarrow, and
the first cost an 8-byte passport error on two string columns
the last time this was written.
