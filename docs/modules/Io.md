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

### WriteLine (RO u: UTF)

Since 0.26 a call of WriteLine is WriteLineUtf, whose heading this is.

_(documented with the group below)_

### Write (RO u: UTF)

Since 0.26 a call of Write is WriteUtf, whose heading this is.

_(documented with the group below)_

### WriteI64 (v: I64)

WriteLine, Write and WriteI64 write to STDOUT: with a newline,
without one, and a decimal integer.  They are buffered, and Halt
below flushes them.  That is why Halt is the only way out of a
program that has written anything.

  u -- the text, written as its UTF-8 octets.  Since 0.26 a
       call of WriteLine or Write is WriteLineUtf's or
       WriteUtf's.  Nothing in this module raises, so these
       three cannot be the call that fails.

### WriteBytes (RO b: SLICE OF BYTE)

WriteBytes writes octets to STDOUT as they are (a stored object,
a PNG) through the SAME buffer as Write.  So earlier writes come
out before them, and Halt flushes both.  (cp-kernel's issue 18,
2026-10-09: writing /dev/stdout with WriteFileBytes overtook the
buffered text and does not exist on Windows.)  Standard output is
binary on every platform.

### ErrLine (RO u: UTF)

Since 0.26 a call of ErrLine is ErrLineUtf, whose heading this is.

_(undocumented)_

### Err (RO u: UTF)

Since 0.26 a call of Err is ErrUtf, whose heading this is.

_(undocumented)_

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

### ParseI64 (RO s: UTF) : I64 RAISES ValueRange

Since 0.26 a call of ParseI64 is ParseI64Utf, whose heading this is.

_(undocumented)_

### Run (RO cmd: UTF) : I64 RAISES ValueRange

Since 0.26 a call of Run is RunUtf, whose heading this is.

_(undocumented)_

### Env (VAR pool: POOL ; RO name: UTF) : UTF RAISES ValueRange

Since 0.26 a call of Env is EnvUtf, whose heading this is.

EnvUtf answers the value's bytes validated as UTF-8 (ValueRange
when they are not).  Env answers them one CHAR a byte, so
`UTF (Io.Env (..))` would encode each byte again.

### Exists (RO path: UTF) : BOOL RAISES ValueRange

Since 0.26 a call of Exists is ExistsUtf, whose heading this is.

_(undocumented)_

### ModTime (RO path: UTF) : I64 RAISES ValueRange

Since 0.26 a call of ModTime is ModTimeUtf, whose heading this is.

_(undocumented)_

### Remove (RO path: UTF) : BOOL RAISES ValueRange

Since 0.26 a call of Remove is RemoveUtf, whose heading this is.

_(undocumented)_

### ListDir (VAR pool: POOL ; RO path: UTF) : SLICE OF UTF RAISES IOError, ValueRange

Since 0.26 a call of ListDir is ListDirUtf, whose heading this is.

ListDirUtf raises ValueRange for a name that is not UTF-8, where
ListDir answers it one CHAR a byte.

### Arg (VAR pool: POOL ; i: I64) : UTF RAISES IndexError, ValueRange

Since 0.26 a call of Arg is ArgUtf, whose heading this is.

_(undocumented)_

### ReadFile (RO path: UTF) : UTF RAISES ValueRange, IOError [FRESH]

Since 0.26 a call of ReadFile is ReadFileUtf, whose heading this is.

ReadFileUtf answers the whole file as text: its octets validated
as UTF-8 (ValueRange, with the offset of the first that is not)
and kept as they are.  The answer is a UTF of the file's size,
where ReadFile's STR is four times it.  ReadFileUtf is not
ReadFile's twin by shape: it answers in the caller's frame,
where ReadFile answers into a pool (`UTF (pool, Io.ReadFileUtf
(path))` keeps it)

### ReadFileBytes (VAR pool: POOL ; RO path: UTF) : SLICE OF BYTE RAISES ValueRange, IOError

Since 0.26 a call of ReadFileBytes is ReadFileBytesUtf, whose heading this is.

_(undocumented)_

### WriteFile (RO path: UTF ; RO content: UTF) RAISES ValueRange, IOError

Since 0.26 a call of WriteFile is WriteFileUtf, whose heading this is.

_(documented with the group below)_

### AppendFile (RO path: UTF ; RO content: UTF) RAISES ValueRange, IOError

Since 0.26 a call of AppendFile is AppendFileUtf, whose heading this is.

With WriteFileUtf and AppendFileUtf the file's bytes become, or
gain, content's octets.

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

### FileSize (RO path: UTF) : I64 RAISES ValueRange, IOError

Since 0.26 a call of FileSize is FileSizeUtf, whose heading this is.

_(undocumented)_

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

### MkDir (RO path: UTF) RAISES ValueRange, IOError

Since 0.26 a call of MkDir is MkDirUtf, whose heading this is.

_(undocumented)_

### MkDirs (RO path: UTF) RAISES ValueRange, IOError

Since 0.26 a call of MkDirs is MkDirsUtf, whose heading this is.

_(undocumented)_

### Rename (RO from: UTF ; RO to: UTF) RAISES ValueRange, IOError

Since 0.26 a call of Rename is RenameUtf, whose heading this is.

_(undocumented)_

### WriteFileBytes (RO path: UTF ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

Since 0.26 a call of WriteFileBytes is WriteFileBytesUtf, whose heading this is.

_(undocumented)_

### AppendFileBytes (RO path: UTF ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

Since 0.26 a call of AppendFileBytes is AppendFileBytesUtf, whose heading this is.

_(undocumented)_

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
