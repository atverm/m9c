# Io

Io is the narrowest useful boundary to the outside: standard
output, command-line arguments, whole files.  TEXT crosses the
CHAR/octet line as UTF-8 (since 2026-10-09, Alex: "flip
readfile/writefile to utf8").  A file read as text is decoded
STRICTLY: one that is not UTF-8 raises ValueRange rather than
reading as something it is not.  A file written as text takes
every Unicode scalar, as the console always did.  A path is text
too.  The *Bytes forms move octets and decode nothing.

This module deliberately leaves out streams, seeking, formatted
output, directories.  A file is read or written whole, because that
is what every caller in this repository does and a partial-read API
invites the truncation bugs Http.RecvMax already had to fix.

### WriteLine (RO s: STR)

**Deprecated** (the UTF transition): WriteLineUtf is its UTF form.

_(documented with the group below)_

### Write (RO s: STR)

**Deprecated** (the UTF transition): WriteUtf is its UTF form.

_(documented with the group below)_

### WriteI64 (v: I64)

WriteLine, Write and WriteI64 write to STDOUT: with a newline,
without one, and a decimal integer.  They are buffered, and Halt
below flushes them.  That is why Halt is the only way out of a
program that has written anything.

  s -- CHARs are Unicode scalars and go out as octets; a scalar
       past 255 is the CHAR/octet boundary and belongs to
       DynStr.Bytes, not here.  Nothing in this module raises,
       so these three cannot be the call that fails.

### WriteBytes (RO b: SLICE OF BYTE)

WriteBytes writes octets to STDOUT as they are (a stored object,
a PNG) through the SAME buffer as Write.  So earlier writes come
out before them, and Halt flushes both.  (cp-kernel's issue 18,
2026-10-09: writing /dev/stdout with WriteFileBytes overtook the
buffered text and does not exist on Windows.)  Standard output is
binary on every platform.

### ErrLine (RO s: STR)

**Deprecated** (the UTF transition): ErrLineUtf is its UTF form.

ErrLine writes to STDERR, and flushes.  Diagnostics do not belong
in the program's output stream: the museum's HALT piece is three of
them lost, and a log line interleaved into a data file is the same
accident with a longer fuse.

### Err (RO s: STR)

**Deprecated** (the UTF transition): ErrUtf is its UTF form.

Err writes to STDERR without a newline and flushes: Write's
twin.  It is for text that already carries its line ends, such
as what a child process wrote to its own stderr and System.Exec
handed back whole.  m9c forwards that as it was, not one line at
a time.

### ArgCount () : I64

ArgCount answers how many command-line arguments there are, the
program's own name INCLUDED as argument 0.  That is C's
convention, kept because every caller here is walking argv and
an off-by-one at the boundary is worse than a familiar one.  So
a program with no
arguments answers 1, and Arg (pool, 0) is its own name.

### Halt (code: I64)

Halt flushes stdout AND stderr before exiting.  The museum's HALT
piece is here: three diagnostics were lost to an unflushed
buffer, so a halt that does not flush is the bug, and this one
flushes as its first act.  A program that can fail needs an
exit status; it does not need a silent one.  A code beyond
0 .. 255 exits 255: the system truncates it, and Halt (256) used
to exit 0, a failure reported as success.

### ParseI64 (RO s: STR) : I64 RAISES ValueRange

**Deprecated** (the UTF transition): ParseI64Utf is its UTF form.

ParseI64 reads decimal, with an optional leading '-'.  Anything
else raises: a command
line is input, and input that is not what it claims is exactly
what the checked-conversion story exists for.

### Run (RO cmd: STR) : I64 RAISES ValueRange

**Deprecated** (the UTF transition): RunUtf is its UTF form.

Run hands one command line to the shell and answers its status.
The shell is what knows how cc is spelled here, so m9c does not
have to.  Quoting is the hazard: a caller composing a path into
a command must refuse what it cannot quote rather than compose
something it cannot predict.

### Env (VAR pool: POOL ; RO name: STR) : STR RAISES ValueRange

**Deprecated** (the UTF transition): EnvUtf is its UTF form.

Env answers the variable's value, or empty when it is unset.  Unset
and empty are not distinguished, because no caller here needs to
and a two-valued answer nobody reads is a trap.

### Exists (RO path: STR) : BOOL RAISES ValueRange

**Deprecated** (the UTF transition): ExistsUtf is its UTF form.

Exists answers whether path is readable.  It is a probe, not an
open: the caller that asks this is choosing between candidates.
A read of each one to find out would be an answer bought at the
price of the question.

### ModTime (RO path: STR) : I64 RAISES ValueRange

**Deprecated** (the UTF transition): ModTimeUtf is its UTF form.

ModTime answers when the file was last written, in seconds since
the epoch, or -1 if it cannot be looked at.

It is a COMPARISON, not a clock.  The only caller asks whether
an object file is older than the source it came from, and for
that the ORDER of two answers is all that matters.  That is why
this is a bare integer rather than a Time.Instant.  It is also
why a resolution of one second is not a defect: a build that
rewrites a source and recompiles it inside the same second is a
build whose inputs nobody could have read either.

### Remove (RO path: STR) : BOOL RAISES ValueRange

**Deprecated** (the UTF transition): RemoveUtf is its UTF form.

Remove deletes a file and answers whether it is gone.  A by-product
that cannot be removed is worth a word, not a raise: the object it
came from was still built.

### ListDir (VAR pool: POOL ; RO path: STR) : SLICE OF STR RAISES IOError, ValueRange

**Deprecated** (the UTF transition): ListDirUtf is its UTF form.

ListDir answers the entries of a directory, '.' and '..'
excluded, in the order the filesystem hands them out: readdir
order, NOT sorted.  The zarr proxy must answer ?list with the
same bytes the Python reference gets from the same syscall.

  path -- a directory; anything else RAISES IOError carrying
          the path, the same contract as ReadFile.  An EMPTY
          directory answers an empty slice, which is not an
          error: nothing there and nothing readable are
          different answers.

### Arg (VAR pool: POOL ; i: I64) : STR RAISES IndexError, ValueRange

**Deprecated** (the UTF transition): ArgUtf is its UTF form.

Arg answers argument i as a fresh string in pool, copied out of
the C argv rather than borrowed from it.

  i -- 0 .. ArgCount - 1, and 0 is the program's own name.
       Anything else RAISES IndexError instead of answering the
       empty string.  An argument that was not given and an
       argument that was given empty are different, and a
       command line is exactly where that difference bites.

### ReadFile (VAR pool: POOL ; RO path: STR) : STR RAISES ValueRange, IOError

**Deprecated** (the UTF transition): ReadFileUtf is its UTF form.

ReadFile answers the whole file as text, in one allocation.  There
is no seeking and no partial read anywhere in this module, for the
reason the header gives.

  path -- IOError if it cannot be opened or read; the exception
          carries the path, so the caller need not compose the
          message.  ValueRange is the octet boundary on the
          path itself, not on the contents.

The file is UTF-8 and is decoded as such, strictly: a byte
sequence that is not UTF-8 raises ValueRange (DynStr.FromUtf8).
For anything large, or anything that is not text, use
ReadFileBytes below and read its note first: a CHAR is four
bytes wide, so this quadruples a file in memory.

A file another process is WRITING at that moment is read as
whatever it held when its size was taken, possibly nothing, and
never as an exception.  The size is asked first and the bytes
second, and between the two a writer can fill the file.  A
reader polling for a file the way m9setup polls for the
tutorial's port file met exactly that (2026-09-11).

### ReadFileBytes (VAR pool: POOL ; RO path: STR) : SLICE OF BYTE RAISES ValueRange, IOError

**Deprecated** (the UTF transition): ReadFileBytesUtf is its UTF form.

ReadFileBytes does the same read, as OCTETS.  A CHAR is a Unicode
scalar and so four bytes wide, which is right for text and wrong
for a file: ReadFile on a 207 MB CSV allocates 828 MB and spends a
pass widening bytes nobody wanted widened.  A reader that scans for
commas wants the bytes.  The slice carries one extra zero byte past
the end, so a C string function called on a field inside it cannot
run off the buffer.

### WriteFile (RO path: STR ; RO content: STR) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): WriteFileUtf is its UTF form.

_(documented with the group below)_

### AppendFile (RO path: STR ; RO content: STR) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): AppendFileUtf is its UTF form.

With WriteFile and AppendFile the file's bytes become, or gain,
the UTF-8 of content: every Unicode scalar encoded
(DynStr.Utf8).  Until 2026-10-09 WriteFile narrowed one CHAR to
one octet and refused a scalar past 255, while the console
encoded UTF-8.  So nothing in Io wrote text, and a UTF-8 file
read with ReadFile printed double-encoded.  cp-kernel found it
on 0.18.0 (Io.WriteFile of a string holding U+2082 raised
ValueRange).  A program that holds OCTETS as CHARs, such as an
HTTP body or a request's bytes, writes them through
WriteFileBytes (path, DynStr.Bytes (pool, s, FALSE)).

### ReadStdin (cap: I64) : SLICE OF BYTE

ReadStdin does one read(2) from standard input: up to cap bytes,
and an EMPTY slice at end of input.  The whole-file rule above is
for files; a stream has no whole, and a language server frames its
own messages over this.

  cap -- at most this many bytes; zero or negative answers the
         empty slice without reading.

### Flush ()

Flush pushes buffered output to standard output NOW.  A server
writes a reply and then blocks reading the next request; without
this the reply sits in the buffer and the client waits on the
silence.

### FileSize (RO path: STR) : I64 RAISES ValueRange, IOError

**Deprecated** (the UTF transition): FileSizeUtf is its UTF form.

FileSize answers how many bytes the file holds, without reading
them: the size probe ReadFileBytes has always made first,
exported.  A caller deciding whether to REDO work needs the size
and not the contents.  The field precompute, skipping a file
already written at the right size, is one.  A read of half a
gigabyte to learn a number is not a probe.

### ReadFileHead (VAR pool: POOL ; RO path: STR ; cap: I64) : SLICE OF BYTE RAISES ValueRange, IOError

ReadFileHead answers the first `cap` bytes, or the whole file if
it is shorter.  It is the one bounded read in a module of
whole-file reads, and it exists for headers: a 256-byte probe of
a half-gigabyte field cache decides skip-or-recompute without
touching the payload.

### ReadFileAt (VAR pool: POOL ; RO path: STR ; off: I64 ; cap: I64) : SLICE OF BYTE RAISES ValueRange, IOError

ReadFileAt answers `cap` bytes from `off`, or fewer at the end of
the file, or an EMPTY slice at or past it.  It is the positioned
read the whole-file ones cannot express, and a streaming reader
is built on it: a 9 GB delimited table is walked in blocks, and
a whole read is not an option at any block size.

It is STATELESS: it opens and closes per call rather than
handing back a file handle, because a handle is a lifetime.  M9
would need a type for it, a close that cannot be forgotten, and
an answer for the pool that holds it going away.  One open per
quarter-gigabyte block is not measurable; a handle type is a
permanent piece of API.  A caller reading in small pieces pays
for that choice, and should not.

It takes seekable files only: a plain file is, a pipe is not.

### MkDir (RO path: STR) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): MkDirUtf is its UTF form.

MkDir creates the directory, one level; an existing one is fine.
That is what an output directory needs before the first file
goes into it.

### MkDirs (RO path: STR) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): MkDirsUtf is its UTF form.

MkDirs is mkdir -p: it creates the directory and every missing
parent; an existing one is fine.  `/' separates, and `\' too on
Windows.
IOError names the path where a level could not be made
(cp-kernel's issue 9, 2026-10-09).

### Rename (RO from: STR ; RO to: STR) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): RenameUtf is its UTF form.

Rename is rename(2): atomic replace on one filesystem.  Write the
temp file, Rename over the target, and a reader never sees a
half-written document.

### WriteFileBytes (RO path: STR ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): WriteFileBytesUtf is its UTF form.

WriteFileBytes makes the file's bytes exactly `content`: the twin
of ReadFileBytes, which existed while writing stayed text-only.
WriteFile encodes CHARs, which is right for text and absurd for
a large binary: a 345 MB field cache written through it would
build 1.4 GB of CHARs first.  That cache is what forced this.

### AppendFileBytes (RO path: STR ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

**Deprecated** (the UTF transition): AppendFileBytesUtf is its UTF form.

AppendFileBytes appends the same octets, and creates the file if
it is absent.  It is for a caller who has a STREAM and a
consumer that wants a PATH: a
NOAA ObsPack member is 244 MB of HDF5 inside a zip and libnetcdf
opens a path, so the choice was between one 244 MB buffer and
one 4 MB one.

### EXCEPTION IOError

_(undocumented)_

### WriteUtf (RO u: UTF)

_(documented with the group below)_

### WriteLineUtf (RO u: UTF)

WriteLineUtf writes the line and its LF in one write, as
WriteLine's are.

### ErrLineUtf (RO u: UTF)

_(documented with the group below)_

### ReadFileUtf (RO path: UTF) : UTF RAISES ValueRange, IOError [FRESH]

ReadFileUtf answers the whole file as text: its octets validated
as UTF-8 (ValueRange, with the offset of the first that is not)
and kept as they are.  The answer is a UTF of the file's size,
where ReadFile's STR is four times it.  ReadFileUtf is not
ReadFile's twin by shape: it answers in the caller's frame,
where ReadFile answers into a pool (`UTF (pool, Io.ReadFileUtf
(path))` keeps it)

### WriteFileUtf (RO path: UTF ; RO content: UTF) RAISES ValueRange, IOError

_(documented with the group below)_

### AppendFileUtf (RO path: UTF ; RO content: UTF) RAISES ValueRange, IOError

With WriteFileUtf and AppendFileUtf the file's bytes become, or
gain, content's octets.

### RunUtf (RO cmd: UTF) : I64 RAISES ValueRange

_(documented with the group below)_

### EnvUtf (VAR pool: POOL ; RO name: UTF) : UTF RAISES ValueRange

EnvUtf answers the value's bytes validated as UTF-8 (ValueRange
when they are not).  Env answers them one CHAR a byte, so
`UTF (Io.Env (..))` would encode each byte again.

### ArgUtf (VAR pool: POOL ; i: I64) : UTF RAISES IndexError, ValueRange

_(documented with the group below)_

### ExistsUtf (RO path: UTF) : BOOL RAISES ValueRange

_(documented with the group below)_

### ModTimeUtf (RO path: UTF) : I64 RAISES ValueRange

_(documented with the group below)_

### RemoveUtf (RO path: UTF) : BOOL RAISES ValueRange

_(documented with the group below)_

### FileSizeUtf (RO path: UTF) : I64 RAISES ValueRange, IOError

_(documented with the group below)_

### MkDirUtf (RO path: UTF) RAISES ValueRange, IOError

_(documented with the group below)_

### MkDirsUtf (RO path: UTF) RAISES ValueRange, IOError

_(documented with the group below)_

### RenameUtf (RO from: UTF ; RO to: UTF) RAISES ValueRange, IOError

_(documented with the group below)_

### ListDirUtf (VAR pool: POOL ; RO path: UTF) : SLICE OF UTF RAISES IOError, ValueRange

ListDirUtf raises ValueRange for a name that is not UTF-8, where
ListDir answers it one CHAR a byte.

### ReadFileBytesUtf (VAR pool: POOL ; RO path: UTF) : SLICE OF BYTE RAISES ValueRange, IOError

_(undocumented)_

### WriteFileBytesUtf (RO path: UTF ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

_(undocumented)_

### AppendFileBytesUtf (RO path: UTF ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

_(undocumented)_

### ParseI64Utf (RO s: UTF) : I64 RAISES ValueRange

_(undocumented)_

### ErrUtf (RO u: UTF)

_(undocumented)_

### PutChars (buf: C.ConstPtr ; n: C.SizeT) [REENTRANT]

_(documented with the group below)_

### PutBytes (buf: C.ConstPtr ; n: C.SizeT) [REENTRANT]

_(documented with the group below)_

### PutErrBytes (buf: C.ConstPtr ; n: C.SizeT) [REENTRANT]

PutChars sends CHARs straight out as UTF-8.  Console output is
TOTAL: every Unicode scalar has a UTF-8 encoding.  Unlike
DynStr.Bytes, which narrows to octets for the wire and must
raise, nothing here can fail, and the signature says so.  These
are REENTRANT because the C library's stdout lock makes them so,
which is a fact about glibc, not an assumption.

### ArgC () : C.Int [REENTRANT]

_(documented with the group below)_

### Exit (code: C.Int) [SERIAL]

_(documented with the group below)_

### RunCmd (cmd: C.ConstPtr) : C.Int [SERIAL]

RunCmd is SERIAL: system () forks, and a fork from several
threads while the others hold locks is the classic way to
deadlock a child.  This is stated as a contract rather than
assumed away.

### Access (path: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### Stat (path: C.ConstPtr) : C.SSizeT [REENTRANT]

_(undocumented)_

### LsDir (path: C.ConstPtr ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### Unlink (path: C.ConstPtr) : C.Int [SERIAL]

_(undocumented)_

### GetEnv (name: C.ConstPtr ; buf: C.MutPtr ; cap: C.Int) : C.Int [SERIAL]

_(undocumented)_

### PutErr (buf: C.ConstPtr ; n: C.SizeT) [REENTRANT]

_(undocumented)_

### ReadIn (buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [SERIAL]

_(undocumented)_

### FlushOut () [SERIAL]

_(undocumented)_

### ArgLen (i: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### ArgCopy (i: C.Int ; buf: C.MutPtr ; cap: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### ReadAt (path: C.ConstPtr ; buf: C.MutPtr ; cap: C.SSizeT ; off: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### ReadWhole (path: C.ConstPtr ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CAdopt (p: C.ConstPtr ; n: C.SSizeT ; out: C.MutPtr) : C.SSizeT [REENTRANT]

CAdopt validates the bytes in place and answers them as a UTF
over the same storage (m9rt.h), for ReadFileUtf.  It answers -1,
or the offset of the first byte that is no UTF-8.

### CMkDir (path: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### CRename (from: C.ConstPtr ; to: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### WriteWhole (path: C.ConstPtr ; buf: C.ConstPtr ; n: C.SizeT) : C.Int [REENTRANT]

WriteWhole is REENTRANT, by the same reasoning as ReadWhole: a
private FILE* opened "wb" on this path, written, closed, with no
shared state.  A caller that writes the SAME path from two
threads races, but it raced under SERIAL too (the gate ordered
nothing).  Distinct paths, the zarr writer's case, are safe.
This is what let a threaded
builder serialise 8 workers behind one gate on a slow fs.

### AppendWhole (path: C.ConstPtr ; buf: C.ConstPtr ; n: C.SizeT) : C.Int [REENTRANT]

AppendWhole is REENTRANT: it opens a private FILE* "ab".
O_APPEND makes each write atomic to the file, so two threads
appending distinct files never race
and even the same file interleaves whole records, not bytes.
