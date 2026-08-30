# Csv

A reader for delimited text tables with a column header.

WHAT IT IS FOR.  Numeric tables large enough that the reading is
the cost: instrument timeseries, model output, station archives.
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
down -- not hypothetical: polars, given the file this was first
written for, stops 125 KB in with "could not parse `-2.03` as dtype
`i64`".  Sampling also cannot distinguish a station code from a
number.  So the caller states the schema, and a schema is exactly
the kind of thing that belongs in a file next to the data rather
than in the program (demo/icos-roundtrip has one, derived from its
data provider's published variable dictionary).

MEASUREMENTS ARE F32.  That is what instruments produce and what
NetCDF and Zarr archives of the same data store, so comparing them
is a question about bits rather than tolerances.  Text is parsed to
F32 DIRECTLY, never to F64 and then narrowed: two roundings can
differ from one, and the way not to argue about when is not to do
it.  A caller needing F64 measurements should say so and this grows
a kind; nobody has yet.

TIME IS Time.Instant, which is UTC by construction.  A timestamp
written without a zone -- which is most of them, in this kind of
data -- therefore cannot become an Instant until the caller says
what zone it was written in.  That is the point, not an
inconvenience: it is the difference between an hour of silent error
and a line of configuration.

WHAT IT IS NOT.  Not a general CSV library: no newlines inside
quoted fields (with "" undoubled by TextAt), no ragged rows, no type
inference, no streaming.  Each of those is a real feature for
somebody and none is free, so they arrive when a caller needs
one.

### TYPE Table

_(documented with the group below)_

### TYPE Kind

not parsed; costs only the scan

### TYPE Options

',' unless said otherwise

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

comma, unquoted, one header row, no preamble, no missing value,
UTC.  Every one of those is a decision, so they are in one place
where a reader can see all of them at once.

### Open (VAR pool: POOL ; RO path: STR ; RO opt: Options) : PTR Table IN pool RAISES ParseError, ValueRange, Io.IOError

reads the file and the header and counts the rows; parses no
values, because the caller declares the column kinds first

### Rows (t: PTR Table) : I64

_(documented with the group below)_

### Cols (t: PTR Table) : I64

_(documented with the group below)_

### Name (VAR pool: POOL ; t: PTR Table ; c: I64) : STR RAISES IndexError, ValueRange

_(documented with the group below)_

### Find (t: PTR Table ; RO name: STR) : I64

the column index, or -1.  Not an error: a caller choosing
between conventions needs the question, not the diagnosis

### SetKind (VAR t: PTR Table ; c: I64 ; k: Kind) RAISES IndexError

_(documented with the group below)_

### SetReal (VAR t: PTR Table ; c: I64) RAISES IndexError

_(documented with the group below)_

### SetInt (VAR t: PTR Table ; c: I64) RAISES IndexError

_(documented with the group below)_

### SetText (VAR t: PTR Table ; c: I64) RAISES IndexError

_(documented with the group below)_

### SetSkip (VAR t: PTR Table ; c: I64) RAISES IndexError

_(documented with the group below)_

### SetStamp (VAR t: PTR Table ; c: I64 ; format: I64) RAISES IndexError

the same thing as SetKind, said without naming the variant.  An
M9 caller in another module cannot write `Csv.Kind.Real` today:
the checker resolves a cross-module payload-less variant
constructor and the GENERATOR refuses it -- "unknown name: Csv".
Logged as a gap between the two rather than papered over; a C
caller can still pass a Kind.

### CONST KindSkip

_(documented with the group below)_

### CONST KindReal

_(documented with the group below)_

### CONST KindInt

_(documented with the group below)_

### CONST KindStamp

_(documented with the group below)_

### CONST KindText

_(documented with the group below)_

### KindCodeAt (t: PTR Table ; c: I64) : I64 RAISES IndexError

_(documented with the group below)_

### FormatAt (t: PTR Table ; c: I64) : I64 RAISES IndexError

the kind the caller set (KindSkip until set) and, for a Stamp
column, its format.  Added for Frame.m9, which walks a parsed
table and must ask rather than guess.

### Parse (VAR pool: POOL ; VAR t: PTR Table) RAISES ParseError, RangeError, ValueRange, IndexError

one pass over the whole file

### ColF32 (t: PTR Table ; c: I64) : SLICE OF F32 RAISES IndexError

_(documented with the group below)_

### ColI64 (t: PTR Table ; c: I64) : SLICE OF I64 RAISES IndexError

_(documented with the group below)_

### ColStamp (t: PTR Table ; c: I64) : SLICE OF Time.Instant RAISES IndexError

_(documented with the group below)_

### TextAt (VAR pool: POOL ; t: PTR Table ; c, row: I64) : STR RAISES IndexError, ValueRange

a text field, built on demand out of the file still in memory: a
table of a hundred thousand rows does not want a hundred
thousand strings nobody asked for

### StrToF32 (s: C.ConstPtr) : C.Double [REENTRANT]

the runtime's one-line shim over strtof, not strtof itself:
C.ConstPtr is `const void *` and stdlib.h has already declared
strtof with `const char *`, so a direct binding collides.  The
same collision m9_cstrlen answers, and the second instance of
it -- a libc function the runtime header prototypes cannot be
bound directly today.

The answer is a C.Double because M9 has no C.Float.  It carries
exactly the float strtof computed: widening is exact, and the
conversion back to F32 in FieldF32 is the identity, so the
reader still parses decimal text to F32 with ONE rounding.

REENTRANT: strtof reads the C locale, which this never
changes.
