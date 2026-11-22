# Parquet

Parquet reads and writes a subset for Frame.m9: flat schemas.
pyarrow is the oracle both ways: files pyarrow wrote are read
value-exact against what pyarrow reads from them
(corpus/ParquetTest.m9), files this module writes are read back by
pyarrow (runtime/test/columnar.sh).

THE READER reads what pyarrow and polars write with their DEFAULTS:
several row groups, several data pages a chunk (version 1 or 2), a
dictionary page with RLE_DICTIONARY indices (and PLAIN_DICTIONARY,
its old name), PLAIN values, RLE booleans, and pages compressed
with SNAPPY, GZIP or ZSTD or not at all.  Everything outside that is
refused BY NAME: a codec (brotli, lz4), an encoding (the DELTA
family, BYTE_STREAM_SPLIT), a nesting, a repeated column.  A
half-read Parquet file is a numbers-shaped lie.  An OPTIONAL
column's null is the arm's own missing value, the mapping CSV import
applies to an empty field; a null BOOLEAN is refused, BOOL keeping
no missing value.  Strings are UTF-8 both ways.

THE WRITER emits one row group, one PLAIN data page a column, no
dictionary, compressed as Options.codec asks (none by default).
Its columns are REQUIRED by default: Frame's missing values live in
the data (NaN, the sentinels), not as Parquet nulls, so no
definition levels are written.  Asked for (`Options.nulls`,
WriteOpt), every numeric column is OPTIONAL and a missing cell is a
NULL.  That is what pyarrow writes from pandas, and what a reader
that knows no sentinel needs.

### Write (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### WriteTs (VAR pool: POOL ; KEPT ts: PTR Frame.Ts ; RO path: STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

the time axis becomes an INT64 column 'time' (epoch seconds),
and the resolution, convention and description ride in the
file-level key_value_metadata, so TsRead answers the same
frame back

### WriteX (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR ; RO kvK: SLICE OF STR ; RO kvV: SLICE OF STR ; RO nsCols: SLICE OF STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

WriteX is Write plus two things a data service needs: file-level
key_value_metadata pairs (the zarr proxy rides its JSON-LD
data passport under 'data_passport', as pyarrow's writer
does), and INT64 columns named in nsCols annotated as
TIMESTAMP(NANOS, adjusted-to-UTC).  pyarrow then reads a real
timestamp[ns] column, not a bare integer.

### BytesX (VAR pool: POOL ; f: PTR Frame.Fr ; RO kvK: SLICE OF STR ; RO kvV: SLICE OF STR ; RO nsCols: SLICE OF STR) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange, Overflow, IndexError

BytesX answers WriteX's document, IN MEMORY, for a caller that is
answering a request rather than filling a directory.  The whole
file was already assembled in a buffer before WriteX touched the
disk; this hands that buffer over instead, so a server does not
need a per-request temp file it must then read back and remove.
It raises no Io.IOError, because nothing is opened.

### CONST CodecNone

_(undocumented)_

### CONST CodecSnappy

_(undocumented)_

### CONST CodecGzip

_(undocumented)_

### CONST CodecZstd

_(undocumented)_

### TYPE Options

Options holds what WriteX takes, and three things a dataframe
written for pandas and pyarrow needs.  The cp-kernel's time
series renditions (2026-10-09), which pyarrow writes from pandas,
found them:

  usCols -- INT64 columns (microseconds since the epoch)
            annotated TIMESTAMP(MICROS, isAdjustedToUTC false):
            pandas' naive datetime64[us], a time WITHOUT a zone
            said.  nsCols, which says UTC, is the other one;
            a column in both is BadArg.
  i8Cols -- I16 or I32 columns written as INT32 annotated
            INT_8, which pyarrow reads as int8: Frame has no
            signed 8-bit arm (BYTE is unsigned, written UINT_8).
            A value outside -128 .. 127 is BadArg, the column
            named; a missing cell is not looked at when nulls.
  nulls  -- every column but BOOL and STR is OPTIONAL, and a
            cell that is the column's missing value (or NaN, in
            a real column) is a NULL: definition levels, one
            bit-packed run, and the value left out.  FALSE
            writes WriteX's bytes.

  codec  -- every page compressed so, and said in the column's
            metadata; another number is BadArg.

A zeroed record is WriteX with nothing asked: empty slices,
nulls FALSE, CodecNone.  Every name in usCols and i8Cols must be a column
of the frame of the right kind, or BadArg says which (nsCols is
not held to the frame, as WriteX never held it).

- `kvK, kvV : SLICE OF STR` -- file-level key_value_metadata
- `nsCols : SLICE OF STR` -- INT64 as TIMESTAMP(NANOS, UTC)
- `usCols : SLICE OF STR` -- INT64 as TIMESTAMP(MICROS, local)
- `i8Cols : SLICE OF STR` -- an I16 or I32 column as INT_8
- `nulls : BOOL` -- missing cells as Parquet nulls
- `codec : I64` -- CodecNone, CodecSnappy, CodecGzip, CodecZstd

### WriteOpt (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR ; RO o: Options) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### BytesOpt (VAR pool: POOL ; f: PTR Frame.Fr ; RO o: Options) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange, Overflow, IndexError

BytesOpt answers WriteOpt's document in memory, as BytesX is
WriteX's.

### Read (VAR pool: POOL ; RO path: STR) : PTR Frame.Fr RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### TsRead (VAR pool: POOL ; RO path: STR) : PTR Frame.Ts RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

These are libzstd's one-shot calls.  Each makes and frees its own
context, so any number of threads may call them at once.  An error is
a size_t near 2 ** 64, which I64 () refuses with ValueRange.

### ZstdDecompress (dst: C.MutPtr ; cap: C.SizeT ; src: C.ConstPtr ; n: C.SizeT) : C.SizeT [REENTRANT]

_(undocumented)_

### ZstdCompress (dst: C.MutPtr ; cap: C.SizeT ; src: C.ConstPtr ; n: C.SizeT ; level: C.Int) : C.SizeT [REENTRANT]

_(undocumented)_

### ZstdBound (n: C.SizeT) : C.SizeT [REENTRANT]

_(undocumented)_
