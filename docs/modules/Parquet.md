# Parquet

A deliberately MINIMAL Parquet subset for Frame.m9: flat schemas,
PLAIN encoding, uncompressed pages, one row group.  Everything
outside the subset is refused BY NAME -- a codec, an encoding, a
nesting -- because a half-read Parquet file is a numbers-shaped
lie, and the format's long tail (dictionaries, ten codecs, three
page versions, bloom filters) is exactly the part nothing here
needs yet.  docs/dataframe-plan.md phase 4; pyarrow is the oracle
in runtime/test/parquet_driver.c: files pyarrow wrote are read
value-exact, files this module writes are re-read by pyarrow, and
the two refusal samples (dictionary, snappy) are pyarrow's own.

THE WRITER EMITS REQUIRED COLUMNS: Frame's missing values live in
the data (NaN, the sentinels), not as Parquet nulls, so no
definition levels are written.  THE READER accepts OPTIONAL
columns and maps a null to the arm's own missing value -- the
same mapping CSV import applies to an empty field.

Strings are ASCII in this subset, both directions, refused
otherwise with the column named: CHAR beyond 127 would need real
UTF-8 transcoding and nothing here needs it yet.

### EXCEPTION Bad

the refusal, always naming what was met: 'codec 1 (snappy)',
'encoding 8 (RLE_DICTIONARY)', 'nested schema', ...

### Write (VAR pool: POOL ; f: PTR Frame.Fr ; RO path: STR) RAISES Io.IOError, Bad, ValueRange, Overflow, IndexError

_(undocumented)_

### WriteTs (VAR pool: POOL ; ts: PTR Frame.Ts ; RO path: STR) RAISES Io.IOError, Bad, ValueRange, Overflow, IndexError

the time axis becomes an INT64 column 'time' (epoch seconds),
and the resolution, convention and description ride in the
file-level key_value_metadata, so TsRead answers the same
frame back

### Read (VAR pool: POOL ; RO path: STR) : PTR Frame.Fr RAISES Io.IOError, Bad, ValueRange, Overflow, IndexError

_(undocumented)_

### TsRead (VAR pool: POOL ; RO path: STR) : PTR Frame.Ts RAISES Io.IOError, Bad, ValueRange, Overflow, IndexError

_(undocumented)_
