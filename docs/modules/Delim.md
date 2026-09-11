# Delim

A ROW CURSOR over a delimited text file, in bounded memory.

WHY THIS AND NOT Csv.  `Csv` reads a whole file and hands out
finished columns, which is right for the tables it was built for
and impossible for the one this exists for: SOCAT's synthesis
product is a 9 GB tab-separated table of 44 million observations,
and the store builder walks it once, accumulating into zarr chunks
as it goes.  Nothing may hold the file, and nothing may hold the
rows.

AND M9 POOLS DO NOT RESET, which decides the interface.  A reader
answering a fresh STR per row would allocate 44 million of them
and never give one back -- roughly 35 GB for this file, since a
CHAR is four bytes.  So a field is a SLICE OF BYTE VIEWING the
reader's own buffer, valid only until the next `Next`, and the
caller converts the few fields it wants.  Comparing a field
against a literal (`Is`) and reading a number out of it allocate
NOTHING, which is what a 44-million-row walk needs; `Text` copies,
and is for the fields a row does not have many of.

THE PREAMBLE IS JUST ROWS, which is worth saying because the
reference could not do it: SOCAT's file carries a dataset listing
before the data header, and Python must read it with `readline()`
rather than iterating the file, because a text iterator's
read-ahead swallows data rows.  A cursor has no read-ahead to
swallow anything -- read lines until the header, then keep going.

NOT A CSV PARSER.  There are no quotes, no escapes and no embedded
newlines: a line ends at LF and a field ends at the delimiter.
That is what the scientific tab-separated products are, and a
reader that pretended otherwise would be slower and no more
correct for them.  A trailing CR is dropped, so a CRLF file reads
the same as an LF one.

### TYPE Reader

opaque; lives in a POOL

### EXCEPTION Error

_(undocumented)_

### CONST DefaultBlock

1 MiB; SOCAT's own is 256 MiB

### CONST MaxFields

_(documented with the group below)_

### Open (VAR pool: POOL ; RO KEPT path: STR ; delim: BYTE ; block: I64) : PTR Reader IN pool RAISES Error, Io.IOError, ValueRange

`block` is the read size AND the longest line the reader will
accept: a line that does not fit raises rather than being cut,
because a silently truncated row is a wrong measurement.  Pass
0 for DefaultBlock.

### OpenPush (VAR pool: POOL ; delim: BYTE ; block: I64) : PTR Reader IN pool RAISES Error

the same cursor over bytes the CALLER supplies, for a source
that is not a seekable file.  SOCAT's table is the case: it
lives inside a zip, and `Zip.Read` hands out inflated blocks.

THIS IS WHY Delim DOES NOT IMPORT Zip.  M9 has no procedure
types, so a source cannot be passed as a function; the choice
was between this module importing the zip reader -- putting
zlib in the link of every program that reads a plain CSV -- and
letting the caller push.  Pushing costs the caller a loop and
costs everyone else nothing.

The loop is:

  LOOP
    WHILE Next (r) DO ... END ;
    IF NOT Hungry (r) THEN EXIT END ;
    got := <read some bytes> ;
    IF got = 0 THEN Finish (r) ELSE Feed (r, ...) END
  END

### Feed (VAR r: PTR Reader ; RO src: SLICE OF BYTE) : I64 RAISES Error, ValueRange

copy as much of `src` as fits, answering how much was taken.
Zero means the buffer is full while no line has been consumed,
which for a well-formed file means the line is longer than the
block -- the same refusal the file reader makes.

### Finish (VAR r: PTR Reader)

no more bytes are coming.  The last partial line, if there is
one, becomes a line -- a final row without a newline is a row.

### Hungry (r: PTR Reader) : BOOL

TRUE when the reader cannot produce a line without more bytes --
which a FRESH push reader can not, so it starts hungry.  A
file-backed reader never answers TRUE: it refills itself.

### Next (VAR r: PTR Reader) : BOOL RAISES Error, Io.IOError, ValueRange

advance to the next line, FALSE at end of file.  A final line
without a newline is a line.

### Count (r: PTR Reader) : I64

fields in the current line.  An empty line has one field, which
is empty -- str.split's answer, not str.split()'s.

### Field (r: PTR Reader ; i: I64) : SLICE OF BYTE RAISES IndexError

a VIEW into the reader's buffer, valid until the next Next.

### Line (r: PTR Reader) : SLICE OF BYTE

the whole current line, newline and any trailing CR removed.

### LineNo (r: PTR Reader) : I64

_(documented with the group below)_

### Offset (r: PTR Reader) : I64

bytes consumed, for a progress line over a 9 GB file.

### Is (r: PTR Reader ; i: I64 ; RO s: STR) : BOOL RAISES IndexError

field i equals the ASCII literal s, comparing OCTETS and
allocating nothing.  A scalar in s above 127 answers FALSE
rather than raising: this is a fast path, and a non-ASCII
literal is a caller's mistake that Text would show.

### Text (VAR pool: POOL ; r: PTR Reader ; i: I64) : STR RAISES IndexError, ValueRange

field i decoded from UTF-8 into pool.  This ALLOCATES; on a hot
row loop use Is or the number readers instead.

### F32At (r: PTR Reader ; i: I64 ; VAR ok: BOOL) : F32 RAISES IndexError, ValueRange

the field as float32, `ok` FALSE when it is empty or not a
number -- which is how a missing value arrives, and not an
error: SOCAT writes NaN, others write nothing at all.

### F64At (r: PTR Reader ; i: I64 ; VAR ok: BOOL) : F64 RAISES IndexError, ValueRange

the field at FULL precision, through strtod.

NOT the same as widening F32At, and the difference is a real one:
F32At parses with strtof, so a value that is then ARITHMETIC-ed
before being stored has already lost the bits the arithmetic
needed.  Found by differential -- SOCAT's longitude is wrapped
from 0..360 into -180..180 and only then narrowed, and parsing to
float32 first put 19,150 of 20,000 values one ulp out.  Parse
wide, compute wide, narrow once.

### I64At (r: PTR Reader ; i: I64 ; VAR ok: BOOL) : I64 RAISES IndexError, ValueRange

_(undocumented)_

the two libc converters m9rt already wraps for Csv and Json: the
shortest-round-trip float parse, and strtoll

### StrToF (s: C.ConstPtr) : C.Double [REENTRANT]

_(undocumented)_

### StrToD (s: C.ConstPtr) : C.Double [REENTRANT]

_(undocumented)_
