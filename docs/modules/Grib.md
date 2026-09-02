# Grib

ecCodes: GRIB 1 and GRIB 2 messages, read.

Written for the dispersion-model port, whose wind fields arrive this way.
The model's own usage is the specification for this surface --
grib_open_file, grib_new_from_file, grib_get_int, grib_get_real,
grib_get_size, grib_get_string, grib_multi_support_on and
grib_release, wrapped in a grib_check that halts.  What is here is
those, and nothing yet for writing: no caller has asked.

WHAT THE BINDING FIXES ABOUT THE C API.

ecCodes reports through an int and expects every caller to test
it; the ported model tests it 111 times through a macro that stops the
program.  Here a bad code is an Error carrying the operation, the
key it was reading, the library's own message and the number.  A
reader that halts cannot be tested, and a reader of somebody
else's data will meet a bad message eventually.

A KEY THAT IS NOT THERE is not an error in the same sense as a
corrupt file, so Has answers the question without raising.  GRIB
is a format where the sensible thing to do about a missing key is
usually to try another one.

THREADS, AND THE ANNOTATION IS SPLIT BECAUSE THE MEASUREMENT SAID
SO.  This module used to declare everything [SERIAL] on the
argument that ecCodes has a process-wide context and the Debian
build compiles its mutexes out -- the blosc museum piece.  The
argument was never tested, and when it was it did not hold.

What was measured (2026-08-25, the port's gribcold_probe.c).
Debian's libeccodes really does have ZERO pthread_mutex
relocations, and in the 2.48 source the mutex is an empty class
when GRIB_PTHREADS=0.  So the decode runs unprotected, and the
probe tries hard to catch it: the index is built from the GRIB
headers WITHOUT ecCodes, so the first library call in the process
is made by N threads at once; a barrier releases them at that
instant; round-robin makes them load different code tables
together.  **100 fresh processes at 24 threads on a global field
and 60 on a nested one: 0 wrong values, 0 crashes**, with peak RSS
146 -> 170 MB, which is thread stacks and not duplicated caches.

The source says why.  What a DECODE shares is append-only caches
-- the action-file list, the code tables, the key-name tries --
and per-handle counters; losing a race there costs a duplicate
parse or a leaked entry, not a wrong value.  What a FILE WALK
shares is the file pool and the multi-field state, which are
mutated in place.

So: the accessors and FromBytes are [REENTRANT], and Open, Close,
Next, Count and MultiSupport stay [SERIAL].  Two conditions come
with it, and a caller who ignores them is on their own -- decode
ONE file serially first so that no lazy initialisation ever
happens concurrently (Windfields.Readwind reads its first field
with threads = 1 for exactly this reason), and hold parallel
decoding to a differential test, because 160 clean runs of two
message shapes is an argument and not a proof.

### TYPE File

an open GRIB file

### TYPE Message

one decoded message from it

### TYPE Index

where each message begins

### EXCEPTION Error

_(documented with the group below)_

### EXCEPTION SizeError

_(documented with the group below)_

### Open (VAR pool: POOL ; RO KEPT path: STR) : PTR File IN pool RAISES Error, ValueRange

_(documented with the group below)_

### Close (VAR f: PTR File)

closing a file nobody can read from cannot fail in a way a
caller could act on, so this does not raise

### Count (f: PTR File) : I64 RAISES Error

how many messages the file holds.  Rewinds nothing: ecCodes
counts by scanning, so a call in the middle of a read walk is a
mistake the C API will not tell you about, and neither can this
-- stated because it is the one sharp edge left.

### Next (VAR pool: POOL ; f: PTR File ; VAR ok: BOOL) : PTR Message IN pool RAISES Error

the next message, with ok FALSE at end of file.  End of file is
not an error: it is how a walk stops.

### BuildIndex (VAR pool: POOL ; RO data: SLICE OF BYTE) : Index RAISES Error, ValueRange, IndexError

where every message in a file begins and how long it is, found
by walking the GRIB HEADERS ALONE -- no ecCodes, no handle, no
definitions.  "GRIB" at the start, the edition in byte 7, the
total length in bytes 8..15 (edition 2) or 4..6 (edition 1), and
"7777" at the end, which is checked rather than assumed: a
length that does not land on the trailer is a corrupt file and
is refused here instead of becoming a wrong answer later.

WHY IT EXISTS.  ecCodes' own walk builds a handle per message to
find the next one -- 0.134 s of a 0.379 s Readwind on a global
ERA5 field -- and a handle can only be built by one thread at a
time in a library whose file pool is a process-wide singleton.
An index costs a few milliseconds, needs no library at all, and
hands each message to whichever thread wants it.

### FromBytes (VAR pool: POOL ; RO data: SLICE OF BYTE ; off, len: I64) : PTR Message IN pool RAISES Error, ValueRange, IndexError

one message, decoded from bytes already in memory rather than
read from a file.  Answers the same Message a walk answers, so
every accessor below works on it unchanged.

This is the [REENTRANT] half of the module -- see THREADS.

### Release (VAR m: PTR Message)

every message a walk takes must be released, and the handle is
the library's, not the pool's.  A message used after Release is
the use-after-free this language is supposed to make hard, and
it is the reason Release takes VAR and clears the handle: the
next call answers a diagnosis rather than reading freed memory.

### Has (m: PTR Message ; RO key: STR) : BOOL RAISES ValueRange

_(documented with the group below)_

### GetI64 (m: PTR Message ; RO key: STR) : I64 RAISES Error, ValueRange

_(documented with the group below)_

### GetF64 (m: PTR Message ; RO key: STR) : F64 RAISES Error, ValueRange

_(documented with the group below)_

### GetStr (VAR pool: POOL ; m: PTR Message ; RO key: STR) : STR RAISES Error, ValueRange

_(documented with the group below)_

### Size (m: PTR Message ; RO key: STR) : I64 RAISES Error, ValueRange

the number of elements a key holds -- for `values`, the number
of grid points

### Values (m: PTR Message ; out: SLICE OF F64) RAISES Error, SizeError, ValueRange

the decoded field.  LEN (out) must be Size (m, 'values'), and is
checked here rather than trusted: the C call takes a length by
pointer and will happily write what the caller claimed there
was room for.

### Floats (m: PTR Message ; RO key: STR ; out: SLICE OF F32) RAISES Error, SizeError, ValueRange

the same, into single precision, because that is what some
readers do and it is not the same answer.  the model's buffer is
`real(kind=4) :: zsec4` and it reads through
grib_get_real4_array, so every value the model sees has been
rounded to float32 first.

Measured on 20 messages of an ERA5 file: 31,461 of 1,303,200
values differ from the double read, by at most one float32 ULP.
A port that reads doubles here cannot be held to the original
bit for bit, so the port reads floats and says why.

### Doubles (m: PTR Message ; RO key: STR ; out: SLICE OF F64) RAISES Error, SizeError, ValueRange

any double array, by key, with the same length check.  `values`
is the common one and has its own name above; this is for the
others -- `pv`, the vertical coordinate coefficients, which
the model's grid check reads to build akm and bkm.

### ReadGrid2 (VAR pool: POOL ; m: PTR Message) : GRID 2 OF F64 RAISES Error, SizeError, ValueRange

the field as Nj by Ni, the shape the message declares.  Latitude
first, because that is the order the values are stored in and
the order every GRIB tool prints them.

### MultiSupport (on: BOOL)

GRIB 2 multi-field messages: several fields in one message, off
by default in ecCodes and turned on by every model that reads
ECMWF data.  A process-wide switch, which is why it takes no
handle and why the module is honest about that.

libeccodes, verbatim, plus the two libc calls its file API
obliges: ecCodes takes a FILE *, so a caller must fopen.

[SERIAL] on what mutates the process-wide context -- the file
pool, the multi-field switch, the counting walk.  [REENTRANT] on
the accessors and on building a handle from bytes, which share
only append-only caches.  Measured, not assumed: see THREADS in
the definition above.

### COpen (path: C.ConstPtr ; mode: C.ConstPtr) : C.MutPtr [SERIAL]

_(documented with the group below)_

### CClose (f: C.MutPtr) : C.Int [SERIAL]

_(documented with the group below)_

### CLen (s: C.ConstPtr) : C.SSizeT [REENTRANT]

the runtime's shim, not strlen itself: C.ConstPtr is
`const void *` and string.h has already declared strlen with
`const char *`, so the foreign declaration would collide

### NewFromFile (ctx: C.MutPtr ; f: C.MutPtr ; err: C.MutPtr) : C.MutPtr [SERIAL]

_(documented with the group below)_

### HandleDelete (h: C.MutPtr) : C.Int [REENTRANT]

_(documented with the group below)_

### CountInFile (ctx: C.MutPtr ; f: C.MutPtr ; n: C.MutPtr) : C.Int [SERIAL]

_(documented with the group below)_

### NewFromMessage (ctx: C.MutPtr ; data: C.ConstPtr ; n: C.SizeT) : C.MutPtr [REENTRANT]

the bytes stay the caller's and must outlive the handle: ecCodes
does not copy them.  Grib.FromBytes keeps that promise by taking
the whole file's slice and never freeing it first.

### GetLong (h: C.MutPtr ; key: C.ConstPtr ; v: C.MutPtr) : C.Int [REENTRANT]

the out parameter is a C long.  On LP64 that is int64_t, which
is what C.SSizeT maps to; the same ABI identity Http states for
ssize_t.  A 32-bit long would need its own type, and this says
so rather than discovering it on a platform nobody tested.

### GetDouble (h: C.MutPtr ; key: C.ConstPtr ; v: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### GetSize (h: C.MutPtr ; key: C.ConstPtr ; n: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### GetString (h: C.MutPtr ; key: C.ConstPtr ; v: C.MutPtr ; n: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### GetDoubleArray (h: C.MutPtr ; key: C.ConstPtr ; v: C.MutPtr ; n: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### GetFloatArray (h: C.MutPtr ; key: C.ConstPtr ; v: C.MutPtr ; n: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### IsDefined (h: C.MutPtr ; key: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### MultiOn (ctx: C.MutPtr) [SERIAL]

_(undocumented)_

### MultiOff (ctx: C.MutPtr) [SERIAL]

_(undocumented)_

### ErrMessage (code: C.Int) : C.ConstPtr [SERIAL]

_(undocumented)_

### CCopy (d: C.MutPtr ; s: C.ConstPtr ; n: C.SizeT) : C.MutPtr [REENTRANT]

_(undocumented)_
