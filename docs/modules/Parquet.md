# Parquet

A deliberately MINIMAL Parquet subset for Frame.m9: flat schemas,
PLAIN encoding, uncompressed pages, one row group.  Everything
outside the subset is refused BY NAME -- a codec, an encoding, a
nesting -- because a half-read Parquet file is a numbers-shaped
lie, and the format's long tail (dictionaries, ten codecs, three
page versions, bloom filters) is exactly the part nothing here
needs yet.  docs/dataframe-plan.md phase 4; pyarrow is the oracle
both ways: files pyarrow wrote are read value-exact against what
pyarrow reads from them (corpus/ParquetTest.m9), files this module
writes are read back by pyarrow (runtime/test/columnar.sh), and the
refusal samples (dictionary, snappy, a null boolean) are pyarrow's
own.

THE WRITER EMITS REQUIRED COLUMNS by default: Frame's missing
values live in the data (NaN, the sentinels), not as Parquet
nulls, so no definition levels are written.  Asked for
(`Options.nulls`, WriteOpt), every numeric column is OPTIONAL and
a missing cell is a NULL -- what pyarrow writes from pandas, and
what a reader that knows no sentinel needs.  THE READER accepts
OPTIONAL columns and maps a null to the arm's own missing value --
the same mapping CSV import applies to an empty field.

Strings are ASCII in this subset, both directions, refused
otherwise with the column named: CHAR beyond 127 would need real
UTF-8 transcoding and nothing here needs it yet.

### Write (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### WriteTs (VAR pool: POOL ; ts: PTR Frame.Ts ; RO path: STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

the time axis becomes an INT64 column 'time' (epoch seconds),
and the resolution, convention and description ride in the
file-level key_value_metadata, so TsRead answers the same
frame back

### WriteX (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR ; RO kvK: SLICE OF STR ; RO kvV: SLICE OF STR ; RO nsCols: SLICE OF STR) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

Write plus two things a data service needs: file-level
key_value_metadata pairs (the zarr proxy rides its JSON-LD
data passport under 'data_passport', as pyarrow's writer
does), and INT64 columns named in nsCols annotated as
TIMESTAMP(NANOS, adjusted-to-UTC) -- pyarrow then reads a real
timestamp[ns] column, not a bare integer.

### BytesX (VAR pool: POOL ; f: PTR Frame.Fr ; RO kvK: SLICE OF STR ; RO kvV: SLICE OF STR ; RO nsCols: SLICE OF STR) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange, Overflow, IndexError

WriteX's document, IN MEMORY, for a caller that is answering a
request rather than filling a directory.  The whole file was
already assembled in a buffer before WriteX touched the disk;
this hands that buffer over instead, so a server does not need a
per-request temp file it must then read back and remove.  No
Io.IOError, because nothing is opened.

### TYPE Options

file-level key_value_metadata

### WriteOpt (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR ; RO o: Options) RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### BytesOpt (VAR pool: POOL ; f: PTR Frame.Fr ; RO o: Options) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange, Overflow, IndexError

WriteOpt's document in memory, as BytesX is WriteX's

### Read (VAR pool: POOL ; RO path: STR) : PTR Frame.Fr RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_

### TsRead (VAR pool: POOL ; RO path: STR) : PTR Frame.Ts RAISES Io.IOError, Faults.BadArg, ValueRange, Overflow, IndexError

_(undocumented)_
