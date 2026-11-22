# Csv

Csv reads delimited text tables with a column header.

WHAT IT IS FOR.  It is for numeric tables large enough that the
reading is the cost: instrument timeseries, model output, station
archives.
It parses every column in ONE pass and hands out finished storage
afterwards, because a column-at-a-time reader walks the whole file
once per column and there are usually hundreds.

WHAT THE CALLER SAYS, AND WHY THE CALLER RATHER THAN THE READER.
Everything specific to a file is an Option or a per-column Kind:

  the delimiter, whether fields are quoted;
  whether there is a header, and how many preamble lines precede it;
  what each column IS (skipped, real, integer, timestamp, text);
  what a missing value looks like;
  which timezone a naked timestamp was written in.

THERE IS NO TYPE INFERENCE, deliberately.  A reader that samples the
first rows and decides types from them will read a column of
sentinels as an integer and fail on the first real value further
down.  That is not hypothetical: polars, given the file this was
first written for, stops 125 KB in with "could not parse `-2.03` as
dtype `i64`".  Sampling also cannot distinguish a station code from a
number.  So the caller states the schema, and a schema is exactly the
kind of thing that belongs in a file next to the data rather than in
the program (demo/icos-roundtrip has one, derived from its data
provider's published variable dictionary).

MEASUREMENTS ARE F32.  That is what instruments produce and what
NetCDF and Zarr archives of the same data store, so comparing them
is a question about bits rather than tolerances.  Text is parsed to
F32 DIRECTLY, never to F64 and then narrowed: two roundings can
differ from one, and the way not to argue about when is not to do
it.  A caller needing F64 measurements should say so and this grows
a kind; nobody has yet.

TIME IS Time.Instant, which is UTC by construction.  A timestamp
written without a zone (most of them, in this kind of data)
therefore cannot become an Instant until the caller says what zone
it was written in.  That is the point, not an
inconvenience: it is the difference between an hour of silent error
and a line of configuration.

A FIELD THAT IS NOT A NUMBER IS MISSING, NOT ZERO.  A column the
caller declared Real or Real64 is parsed only when the field looks
like a number; anything else reads NaN, exactly as an empty field
does.  strtod answers 0 for text, and a sentence stored as a
measured 0.0 is the worst of the three possible answers.  The ICOS
ocean store found this: 551 comment cells there did precisely
that.  See IsNumber for what counts.

WHAT IT IS NOT.  Csv is not a general CSV library: no ragged rows,
no type inference, no streaming.  A quoted field MAY carry a
newline and a doubled "" (TextAt undoubles it).  Both arrived when
a caller needed them, the FLUXNET shuttle's BADM tables.  Each of
the rest is a real feature for somebody and none is free, so they
arrive the same way.

### TYPE Table

_(documented with the group below)_

### TYPE Kind

not parsed; costs only the scan

### TYPE Options

_(undocumented)_

- `delimiter : CHAR` -- ',' unless said otherwise
- `quoted : BOOL` -- honour "..." around a field
- `header : BOOL` -- a header row names the columns
- `skipLines : I64` -- preamble lines before the header
- `missing : F32` -- a real equal to this becomes NaN
- `hasMissing : BOOL`
- `utcOffset : F64` -- seconds to subtract from a Stamp
- `threads : I64` -- the threads Open and Parse may use; 1
  unless said otherwise.  See Parse.

### CONST StampYmdHm

YYYYMMDDhhmm

### CONST StampYmdHms

YYYYMMDDhhmmss

### CONST StampIso

RFC 3339, via Time.ParseIso

### CONST StampEpoch

seconds since 1970, as a number

### EXCEPTION ParseError

_(documented with the group below)_

### EXCEPTION RangeError

_(documented with the group below)_

### Defaults () : Options

Defaults answers comma, unquoted, one header row, no preamble, no
missing value, UTC, one thread.  Every one of those is a decision, so they are
in one place where a reader can see all of them at once.

### Open (VAR pool: POOL ; RO path: STR ; RO opt: Options) : PTR Table IN pool RAISES ParseError, ValueRange, Io.IOError

Open reads the file and the header and counts the rows.  It
parses no values, because the caller declares the column kinds
first.  Every column is Skip until a setter names it: a column
nobody declared is scanned past, never parsed and never carried.

### OpenBytes (VAR pool: POOL ; RO src: SLICE OF BYTE ; RO opt: Options) : PTR Table IN pool RAISES ParseError, ValueRange

OpenBytes does the same over bytes the caller already holds: a
ZIP member inflated into memory, a body off the wire.  The octets
are COPIED into the table (plus the trailing zero Open's file read
carries), so the caller's buffer is free the moment this returns
and the table never reaches into a pool it does not own.

### Rows (t: PTR Table) : I64

_(documented with the group below)_

### Cols (t: PTR Table) : I64

_(documented with the group below)_

### Name (VAR pool: POOL ; t: PTR Table ; c: I64) : UTF RAISES IndexError, ValueRange

Since 0.26 a call of Name is NameUtf, whose heading this is.

_(documented with the group below)_

### Find (t: PTR Table ; RO name: UTF) : I64

Since 0.26 a call of Find is FindUtf, whose heading this is.

_(undocumented)_

### SetKind (VAR t: PTR Table ; c: I64 ; k: Kind) RAISES IndexError

MEASUREMENTS ARE F32 by default, and the module header says why.
Kind.Real64 is the exception that header names: "a caller needing
F64 measurements should say so and this grows a kind".  The
caller that needed it is the ICOS ocean store, whose every
measurement array is `<f8>`.  A narrowing here and a widening
again to write would be two roundings where the file has one
number.  (SetReal, SetReal64, SetInt, SetText, SetSkip and
SetStamp said the same as SetKind without naming the variant;
deprecated in 0.27.0, removed in 0.28.0.)

### KindAt (t: PTR Table ; c: I64) : Kind RAISES IndexError

_(documented with the group below)_

### IsSet (t: PTR Table ; c: I64) : BOOL RAISES IndexError

IsSet asks whether column c has had its kind named: FALSE while
it is still Skip.  It gives the count of parsed columns without
spelling out every kind at the call site.

### FormatAt (t: PTR Table ; c: I64) : I64 RAISES IndexError

KindAt answers the kind the caller set (Skip until set), and
FormatAt, for a Stamp column, its format.  A caller in another
module CASEs the Kind directly now (the cross-module variant
selector the enumeration work gave the generator); the integer
codes it used to answer against are gone.

### Parse (VAR pool: POOL ; VAR t: PTR Table) RAISES ParseError, RangeError, ValueRange, IndexError

Parse makes one pass over the whole file.

With opt.threads above 1 the file is cut into that many bands at
row ends, and each band is parsed by a thread of its own
(docs/csv-threads-plan.md).  The columns are the same, bit for
bit, as one thread gives, and so is the exception: the one of the
first bad row, with its line.  A band is never cut inside a
quoted field.

After Parse raises, the table's columns are not to be read.  One
thread has stored the rows before the bad one; several have
stored other rows too.

### ColF32 (t: PTR Table ; c: I64) : SLICE OF F32 RAISES IndexError

_(documented with the group below)_

### ColF64 (t: PTR Table ; c: I64) : SLICE OF F64 RAISES IndexError

_(documented with the group below)_

### ColI64 (t: PTR Table ; c: I64) : SLICE OF I64 RAISES IndexError

_(documented with the group below)_

### ColStamp (t: PTR Table ; c: I64) : SLICE OF Time.Instant RAISES IndexError

_(documented with the group below)_

### TextAt (VAR pool: POOL ; t: PTR Table ; c, row: I64) : UTF RAISES IndexError, ValueRange

Since 0.26 a call of TextAt is TextAtUtf, whose heading this is.

_(undocumented)_

### NameUtf (VAR pool: POOL ; t: PTR Table ; c: I64) : UTF RAISES IndexError, ValueRange

_(undocumented)_

### TextAtUtf (VAR pool: POOL ; t: PTR Table ; c, row: I64) : UTF RAISES IndexError, ValueRange

_(undocumented)_

### FindUtf (t: PTR Table ; RO name: UTF) : I64

_(undocumented)_

### StrToF64 (s: C.ConstPtr) : C.Double [REENTRANT]

_(documented with the group below)_

### StrToF32 (s: C.ConstPtr) : C.Double [REENTRANT]

_(documented with the group below)_

### CNumber (p: C.ConstPtr ; n: C.SSizeT) : C.Int [REENTRANT]

_(documented with the group below)_

### CFieldF64 (p: C.ConstPtr ; n: C.SSizeT ; out: C.MutPtr) : C.Int [REENTRANT]

CNumber runs IsNumber's grammar in one pass in the runtime
(m9rt.h, 2026-10-25), and CFieldF64 runs it with the value: 1 a
number, 0 not one, -1 under M9_CSV_PORTABLE.  Then IsNumber and
FieldF64 below decide, the portable twin.  IsNumber and Word were
31% of a CSV read.
