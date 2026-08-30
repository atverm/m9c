# Frame

Dataframes for scientific computing: typed columns that carry
their own metadata and missing value, a timeseries frame that
carries its resolution and time convention, and the two
operations every pipeline otherwise reinvents -- resample-average
and make-contiguous.  docs/dataframe-plan.md is the design; the
oracle is polars, in runtime/test/frame_driver.c.

THE MISSING VALUE LIVES INSIDE THE TYPED ARM, so it can never
have the wrong width for its column -- the ICOS roundtrip demo
got the missing-value rule wrong twice precisely because it lived
outside the data.  For float columns a NaN is ALWAYS missing, on
top of whatever `miss` says; for Strs the empty string is.

THERE IS NO TYPE INFERENCE anywhere here, by the same rule as
Csv.m9: the caller states what a column is, and a frame built
from a CSV inherits the kinds the caller declared there.

Time is I64 SECONDS SINCE THE UNIX EPOCH, UTC, and nothing else:
the roundtrip demo found a "CF time axis" that was silently local
time, an hour of error nobody could see.  A zone is the caller's
problem exactly once, at construction.

### EXCEPTION Unknown

no column of that name

### EXCEPTION WrongType

the accessor's type is not the column's, or a reducer was asked
of a column that cannot answer it (a mean of flags)

### EXCEPTION Duplicate

_(documented with the group below)_

### EXCEPTION SizeError

a column whose length is not the frame's row count; a reducer
slice whose length is not the column count

### EXCEPTION Disorder

the time axis is not strictly increasing at this row, or a
stamp is off the resolution grid

### EXCEPTION BadArg

_(undocumented)_

### TYPE Data

Bools carries NO missing value: a boolean has no spare state,
and a null that silently became FALSE would be the exact lie
this module exists to refuse.  A gap row or a foreign null in a
boolean column REFUSES with the column named.

### TYPE Col

short; the key.  Required, unique.

### TYPE Fr

a plain frame

### TYPE Ts

a timeseries frame: Fr + time axis

### TYPE Conv

the per-column reducer for Average.  Mean answers F64 (polars'
own rule) and is refused on non-float columns; Sum keeps the
column's type and integer sums are overflow-checked; Lo/Hi are
min/max; First/Last are positional within the window, exactly
polars' first()/last().

### TYPE How

_(undocumented)_

### New (VAR pool: POOL ; rows: I64) : PTR Fr IN pool RAISES SizeError

rows < 0 refuses; 0 is a legal empty frame

### AddF64 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF F64 ; miss: F64) RAISES SizeError, Duplicate

_(undocumented)_

### AddF32 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF F32 ; miss: F32) RAISES SizeError, Duplicate

_(undocumented)_

### AddI64 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF I64 ; miss: I64) RAISES SizeError, Duplicate

_(undocumented)_

### AddI32 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF I32 ; miss: I32) RAISES SizeError, Duplicate

_(undocumented)_

### AddI16 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF I16 ; miss: I16) RAISES SizeError, Duplicate

_(undocumented)_

### AddBytes (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF BYTE ; miss: BYTE) RAISES SizeError, Duplicate

_(undocumented)_

### AddBools (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF BOOL) RAISES SizeError, Duplicate

_(undocumented)_

### AddStrs (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; v: SLICE OF STR) RAISES SizeError, Duplicate

the slice is TAKEN, not copied: the frame views the caller's
storage, the AddRoute/Json.Parse retention contract.  Length
must equal the frame's rows.

### SetMeta (VAR pool: POOL ; VAR f: PTR Fr ; RO name, long, cf, unit: STR) RAISES Unknown

'' leaves a field as it was, so one call can set just the unit.
The strings are COPIED into the pool: metadata outlives every
caller's buffer, and the first driver proved it by writing
'units = NOTE' into a file.

### Rows (f: PTR Fr) : I64

_(documented with the group below)_

### Cols (f: PTR Fr) : I64

_(documented with the group below)_

### NameAt (f: PTR Fr ; c: I64) : STR RAISES IndexError

_(documented with the group below)_

### Find (f: PTR Fr ; RO name: STR) : I64

the column index, or -1 -- the question, not the diagnosis

### GetCol (f: PTR Fr ; RO name: STR) : Col RAISES Unknown

the whole column record; CASE over .data handles every type,
and the checker holds the CASE total

### ColF64 (f: PTR Fr ; RO name: STR) : SLICE OF F64 RAISES Unknown, WrongType

_(documented with the group below)_

### ColF32 (f: PTR Fr ; RO name: STR) : SLICE OF F32 RAISES Unknown, WrongType

_(documented with the group below)_

### ColI64 (f: PTR Fr ; RO name: STR) : SLICE OF I64 RAISES Unknown, WrongType

_(documented with the group below)_

### ColStrs (f: PTR Fr ; RO name: STR) : SLICE OF STR RAISES Unknown, WrongType

_(documented with the group below)_

### ColBools (f: PTR Fr ; RO name: STR) : SLICE OF BOOL RAISES Unknown, WrongType

the everyday accessors; the other types go through GetCol

### FromCsv (VAR pool: POOL ; t: PTR Csv.Table) : PTR Fr IN pool RAISES SizeError, Duplicate, IndexError, ValueRange

every non-Skip column of a PARSED Csv.Table, with the kinds the
caller declared there: Real -> F32s (miss NaN), Int -> I64s
(miss MIN I64, stated below), Stamp -> I64s epoch seconds,
Text -> Strs (materialised).  The integer missing value is
-9223372036854775808: an integer column has no NaN, a sentinel
must exist, and the far end of the line is the one value real
data never means.

### WriteCsv (VAR pool: POOL ; f: PTR Fr ; RO path: STR) RAISES Io.IOError, ValueRange, Overflow, IndexError

header = short names; a missing value writes an EMPTY field;
floats write 17 significant digits (round-trip exact -- the
driver proves parse (print (x)) = x bit for bit); a text field
containing the delimiter, a quote or a newline is quoted with
"" doubling.

### CONST KindF64

_(documented with the group below)_

### CONST KindF32

_(documented with the group below)_

### CONST KindI64

_(documented with the group below)_

### CONST KindI32

_(documented with the group below)_

### CONST KindI16

_(documented with the group below)_

### CONST KindByte

_(documented with the group below)_

### CONST KindStr

_(documented with the group below)_

### CONST KindBool

_(documented with the group below)_

### KindOf (f: PTR Fr ; RO name: STR) : I64 RAISES Unknown

_(documented with the group below)_

### ColI32 (f: PTR Fr ; RO name: STR) : SLICE OF I32 RAISES Unknown, WrongType

_(documented with the group below)_

### ColI16 (f: PTR Fr ; RO name: STR) : SLICE OF I16 RAISES Unknown, WrongType

_(documented with the group below)_

### ColBytes (f: PTR Fr ; RO name: STR) : SLICE OF BYTE RAISES Unknown, WrongType

_(documented with the group below)_

### MissF64 (f: PTR Fr ; RO name: STR) : F64 RAISES Unknown, WrongType

_(documented with the group below)_

### MissF32 (f: PTR Fr ; RO name: STR) : F32 RAISES Unknown, WrongType

_(documented with the group below)_

### MissI64 (f: PTR Fr ; RO name: STR) : I64 RAISES Unknown, WrongType

_(documented with the group below)_

### MissI32 (f: PTR Fr ; RO name: STR) : I32 RAISES Unknown, WrongType

_(documented with the group below)_

### MissI16 (f: PTR Fr ; RO name: STR) : I16 RAISES Unknown, WrongType

_(documented with the group below)_

### MissByte (f: PTR Fr ; RO name: STR) : BYTE RAISES Unknown, WrongType

_(documented with the group below)_

### ConvName (conv: Conv) : STR

'start' | 'end' | 'mid'

### WriteNc (VAR pool: POOL ; f: PTR Fr ; RO path, dim: STR) RAISES NetCDF.Error, SizeError, ValueRange, Overflow, IndexError

a netCDF-4 file with one dimension named `dim`, one variable
per column in its OWN storage type, the column's missing value
as a TYPED _FillValue, and units / long_name / standard_name
attributes exactly when the column carries them -- nothing is
invented at export time.  Strs columns become an n x width char
matrix over a per-column length dimension, the PutChars
convention.

### WriteTsNc (VAR pool: POOL ; ts: PTR Ts ; RO path: STR) RAISES NetCDF.Error, SizeError, ValueRange, Overflow, IndexError

WriteNc over the dimension 'time', plus the time coordinate:
I64 seconds, units 'seconds since 1970-01-01 00:00:00 +00:00'
(the zone STATED -- the roundtrip demo found a CF axis that was
silently local time), standard_name time, and time_bnds giving
each stamp's [period start, period end] under the frame's own
convention.  The resolution, convention and description ride as
global attributes so TsFromNc can answer the same frame back.
cell_methods is deliberately NOT written: the frame does not
know whether a column is a mean over its period or a point
sample, and writing 'mean' unasked would be a lie in metadata.

### FromNc (VAR pool: POOL ; RO path, dim: STR) : PTR Fr RAISES NetCDF.Error, BadArg, SizeError, Duplicate, ValueRange, Overflow, IndexError

every variable whose FIRST dimension is `dim`: 1-D numerics
into their matching arms, 2-D char matrices into Strs.  A
variable on the dimension with a type this frame cannot hold is
REFUSED with its name -- a column that silently vanished is the
failure this module exists to prevent.  _FillValue becomes the
column's missing value; units / long_name / standard_name are
read when present.

### TsFromNc (VAR pool: POOL ; RO path: STR) : PTR Ts RAISES NetCDF.Error, BadArg, SizeError, Duplicate, Disorder, ValueRange, Overflow, IndexError

FromNc over 'time', with the time variable itself parsed from
its CF units -- seconds, minutes, hours or days since a date,
any other unit refused with the string.  A nonzero zone offset
in the units is refused too; no zone means UTC, which is CF's
rule and the best that can be done with a file that does not
say.  The convention and resolution come from the global
attributes WriteTsNc writes; a foreign file without them gets
convention start and the axis's own smallest gap, both stated
choices rather than inference.

### NewTs (VAR pool: POOL ; f: PTR Fr ; time: SLICE OF I64 ; res: I64 ; conv: Conv ; RO descr: STR) : PTR Ts IN pool RAISES SizeError, Disorder, BadArg

time is epoch seconds UTC, one per row, STRICTLY increasing and
on the res grid (relative to its own first stamp); res > 0.
Gaps are legal -- MakeContiguous is how they close.

### TsFrame (ts: PTR Ts) : PTR Fr

_(undocumented)_

### TsTime (ts: PTR Ts) : SLICE OF I64

_(undocumented)_

### TsRes (ts: PTR Ts) : I64

_(undocumented)_

### TsConv (ts: PTR Ts) : Conv

_(undocumented)_

### TsDescr (ts: PTR Ts) : STR

_(undocumented)_

### HowMean () : How

_(documented with the group below)_

### HowSum () : How

_(documented with the group below)_

### HowLo () : How

_(documented with the group below)_

### HowHi () : How

_(documented with the group below)_

### HowFirst () : How

_(documented with the group below)_

### HowLast () : How

_(documented with the group below)_

### ConvStart () : Conv

_(documented with the group below)_

### ConvEnd () : Conv

_(documented with the group below)_

### ConvMid () : Conv

_(documented with the group below)_

### Average (VAR pool: POOL ; ts: PTR Ts ; toRes: I64 ; how: SLICE OF How ; minCount: I64) : PTR Ts IN pool RAISES SizeError, WrongType, BadArg, ValueRange, Overflow, IndexError

resample to a coarser resolution.  toRes must be a positive
multiple of the frame's resolution (refused otherwise, named);
how has one entry per column.  Windows are aligned to the epoch
(floor (t / toRes) * toRes over PERIOD-START times, whatever
the convention labels), and only windows containing rows are
emitted -- polars' own group_by_dynamic behaviour; run
MakeContiguous after if a full grid is wanted.  Missing values
are excluded from Mean/Sum/Lo/Hi; a window with fewer than
minCount live values answers the column's missing value.
Output labels follow the frame's own convention at toRes.

### MakeContiguous (VAR pool: POOL ; ts: PTR Ts) : PTR Ts IN pool RAISES SizeError, Duplicate, Disorder, BadArg, WrongType, ValueRange, Overflow, IndexError

every absent period between the first and last stamp becomes a
row of missing values (Strs: '').  The time axis comes out
exactly first..last by res.  A frame with a Bools column
REFUSES (WrongType, the column named): no missing value exists
for a boolean.
