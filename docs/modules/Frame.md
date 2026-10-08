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

### EXCEPTION Disorder

the time axis is not strictly increasing at this row, or a
stamp is off the resolution grid

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

### New (VAR pool: POOL ; rows: I64) : PTR Fr IN pool RAISES Faults.SizeError

rows < 0 refuses; 0 is a legal empty frame

### AddF64 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF F64 ; miss: F64) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddF32 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF F32 ; miss: F32) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddI64 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF I64 ; miss: I64) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddI32 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF I32 ; miss: I32) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddI16 (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF I16 ; miss: I16) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddBytes (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF BYTE ; miss: BYTE) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddBools (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF BOOL) RAISES Faults.SizeError, Duplicate

_(undocumented)_

### AddStrs (VAR pool: POOL ; VAR f: PTR Fr ; RO name: STR ; RO KEPT v: SLICE OF STR) RAISES Faults.SizeError, Duplicate

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

### FromCsv (VAR pool: POOL ; t: PTR Csv.Table) : PTR Fr IN pool RAISES Faults.SizeError, Duplicate, IndexError, ValueRange

every non-Skip column of a PARSED Csv.Table, with the kinds the
caller declared there: Real -> F32s (miss NaN), Int -> I64s
(miss MIN I64, stated below), Stamp -> I64s epoch seconds,
Text -> Strs (materialised).  The integer missing value is
-9223372036854775808: an integer column has no NaN, a sentinel
must exist, and the far end of the line is the one value real
data never means.

### WriteCsv (f: PTR Fr ; RO path: STR) RAISES Io.IOError, ValueRange, Overflow, IndexError

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

### WriteNc (VAR pool: POOL ; f: PTR Fr ; RO KEPT path: STR ; RO dim: STR) RAISES NetCDF.Error, Faults.SizeError, ValueRange, Overflow, IndexError

a netCDF-4 file with one dimension named `dim`, one variable
per column in its OWN storage type, the column's missing value
as a TYPED _FillValue, and units / long_name / standard_name
attributes exactly when the column carries them -- nothing is
invented at export time.  Strs columns become an n x width char
matrix over a per-column length dimension, the PutChars
convention.

### WriteTsNc (VAR pool: POOL ; ts: PTR Ts ; RO KEPT path: STR) RAISES NetCDF.Error, Faults.SizeError, ValueRange, Overflow, IndexError

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

### FromNc (VAR pool: POOL ; RO KEPT path: STR ; RO dim: STR) : PTR Fr RAISES NetCDF.Error, Faults.BadArg, Faults.SizeError, Duplicate, ValueRange, Overflow, IndexError

every variable whose FIRST dimension is `dim`: 1-D numerics
into their matching arms, 2-D char matrices into Strs.  A
variable on the dimension with a type this frame cannot hold is
REFUSED with its name -- a column that silently vanished is the
failure this module exists to prevent.  _FillValue becomes the
column's missing value; units / long_name / standard_name are
read when present.

### TsFromNc (VAR pool: POOL ; RO KEPT path: STR) : PTR Ts RAISES NetCDF.Error, Faults.BadArg, Faults.SizeError, Duplicate, Disorder, ValueRange, Overflow, IndexError

FromNc over 'time', with the time variable itself parsed from
its CF units -- seconds, minutes, hours or days since a date,
any other unit refused with the string.  A nonzero zone offset
in the units is refused too; no zone means UTC, which is CF's
rule and the best that can be done with a file that does not
say.  The convention and resolution come from the global
attributes WriteTsNc writes; a foreign file without them gets
convention start and the axis's own smallest gap, both stated
choices rather than inference.

### NewTs (VAR pool: POOL ; KEPT f: PTR Fr ; KEPT time: SLICE OF I64 ; res: I64 ; conv: Conv ; RO descr: STR) : PTR Ts IN pool RAISES Faults.SizeError, Disorder, Faults.BadArg

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

### Average (VAR pool: POOL ; KEPT ts: PTR Ts ; toRes: I64 ; how: SLICE OF How ; minCount: I64) : PTR Ts IN pool RAISES Faults.SizeError, WrongType, Faults.BadArg, ValueRange, Overflow, IndexError

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

### MakeContiguous (VAR pool: POOL ; KEPT ts: PTR Ts) : PTR Ts IN pool RAISES Faults.SizeError, Duplicate, Disorder, Faults.BadArg, WrongType, ValueRange, Overflow, IndexError

every absent period between the first and last stamp becomes a
row of missing values (Strs: '').  The time axis comes out
exactly first..last by res.  A frame with a Bools column
REFUSES (WrongType, the column named): no missing value exists
for a boolean.

### Take (VAR pool: POOL ; f: PTR Fr ; RO rows: SLICE OF I64) : PTR Fr IN pool RAISES IndexError, Faults.SizeError, Duplicate

f's columns, in f's order, with their metadata, and the rows
named, in the order named; a row may be named more than once,
or not at all.  A number outside 0 .. Rows (f) - 1 is
IndexError.

### Filter (VAR pool: POOL ; f: PTR Fr ; RO mask: SLICE OF BOOL) : PTR Fr IN pool RAISES IndexError, Faults.SizeError, Duplicate

the rows where mask is TRUE, in their order: polars' filter.
LEN (mask) must be Rows (f), or it is Faults.SizeError.

### OrderBy (f: PTR Fr ; RO name: STR ; descending: BOOL) : SLICE OF I64 RAISES Unknown, IndexError

_(documented with the group below)_

### SortBy (VAR pool: POOL ; f: PTR Fr ; RO name: STR ; descending: BOOL) : PTR Fr IN pool RAISES Unknown, IndexError, Faults.SizeError, Duplicate

the rows in the order of one column: OrderBy answers the row
numbers and SortBy the frame, which is Take of them.  STABLE
both ways: rows equal in the column keep the order they had.
The rules are polars' sort with its defaults, a missing value
being its null:

  a missing value comes FIRST, ascending and descending, the
    missing among themselves in the order they had;
  strings by code point, the shorter first, and the empty
    string is a value; FALSE before TRUE.

### GroupBy (VAR pool: POOL ; f: PTR Fr ; RO key: STR ; RO how: SLICE OF How ; minCount: I64) : PTR Fr IN pool RAISES Unknown, WrongType, Faults.SizeError, ValueRange, Overflow, IndexError

one row for every distinct value of the column `key`, the rows
in ASCENDING ORDER OF THE KEY, and the rows whose key is missing
as one group, first (OrderBy's order; polars' group_by, sorted
by the key).  Every other column is reduced over the rows of its
group by its entry of how, which has one entry per column of f,
the key's being ignored: Average's reducers and Average's rules.
Missing values are left out of Mean/Sum/Lo/Hi, a group with
fewer than minCount values left answers the column's missing
value, First and Last are the first and the last ROW of the
group in f's order.  As from Average, an F32 column comes back
F64.

### GroupSizes (f: PTR Fr ; RO key: STR) : SLICE OF I64 RAISES Unknown, IndexError

how many rows each group of GroupBy (f, key) has, in the same
order

### Join (VAR pool: POOL ; a, b: PTR Fr ; RO key: STR) : PTR Fr IN pool RAISES Unknown, WrongType, Duplicate, Faults.SizeError, IndexError

_(documented with the group below)_

### JoinLeft (VAR pool: POOL ; a, b: PTR Fr ; RO key: STR) : PTR Fr IN pool RAISES Unknown, WrongType, Duplicate, Faults.SizeError, IndexError

the rows of a and b that hold the same value in the column
`key`, which both have: a's columns, then b's but its key.  One
row for every PAIR that matches, so a key held twice on each
side gives four; a's rows in a's order and, for each, its
matches in b's order.  Join is the inner join: a row of a that
matches nothing is left out.  JoinLeft keeps it, with the
missing value in every column of b ('' in a Strs column) and
WrongType for a Bools column of b, which has none.

A MISSING KEY MATCHES NOTHING, another missing key included
(polars' rule, and SQL's).  The two key columns must be of one
family: integers of any width with integers, strings with
strings, booleans with booleans.  A REAL key is refused, and a
mismatch is, as WrongType naming the key: equality of two
computed reals is not something to build a table on.  A column
name that a and b share, other than the key, is Duplicate: no
suffix is invented, rename before joining.

### Describe (VAR pool: POOL ; f: PTR Fr) : PTR Fr IN pool RAISES Duplicate, Faults.SizeError, IndexError

nine rows about every NUMERIC column of f: a Strs column
`statistic` naming the rows -- count, missing, mean, std, min,
25%, 50%, 75%, max -- and one F64 column for each numeric column
of f, under its name.  count is of the values that are not
missing; std is the sample one (ddof 1); the percentiles are
Stats.Percentile's, numpy's linear rule (polars' describe with
interpolation = 'linear').  A statistic that has too few values
to exist is NaN.  Strs and Bools columns are left out, and an
I64 beyond 2^53 is rounded on its way to F64.

### TYPE Agg

one number for the values of a group.  v holds the values THAT
ARE THERE, in row order: a missing value is not among them, so
v may be empty, and what a group of nothing answers is the
procedure's to say -- NaN, which is Frame's missing value, is
the honest one.

### TYPE RowFn

one number for a row.  row[j] is the row's value in the j-th
column asked for, and NaN where that is missing -- so plain
arithmetic answers NaN for a row with a gap, which is right.

### TYPE RowTest

yes or no for a row; a comparison with a NaN is FALSE

### Aggregate (VAR pool: POOL ; f: PTR Fr ; RO key, name: STR ; agg: Agg ; RO p: SLICE OF F64) : PTR Fr IN pool RAISES Unknown, WrongType, Duplicate, Faults.SizeError, ValueRange, IndexError

GroupBy's groups, in GroupBy's order, and two columns: the key,
and the column `name' reduced by agg, as F64 with NaN for its
missing value.  polars' group_by (key).agg (an expression over
name), sorted by the key.

### Compute (VAR pool: POOL ; VAR f: PTR Fr ; RO cols: SLICE OF STR ; RO name: STR ; fn: RowFn ; RO p: SLICE OF F64) RAISES Unknown, WrongType, Duplicate, Faults.SizeError, ValueRange, IndexError

a new F64 column `name' ADDED to f, each value fn of that row's
values in the columns cols; its missing value is NaN.  polars'
with_columns.

### FilterBy (VAR pool: POOL ; f: PTR Fr ; RO cols: SLICE OF STR ; test: RowTest ; RO p: SLICE OF F64) : PTR Fr IN pool RAISES Unknown, WrongType, Duplicate, Faults.SizeError, ValueRange, IndexError

the rows for which test is TRUE of their values in the columns
cols, in their order: Filter, with the mask computed here.
polars' filter over an expression, where a null is not a yes.
