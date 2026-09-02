# Io

The narrowest useful boundary to the outside: standard output,
command-line arguments, whole files.  Everything here crosses the
CHAR/octet line, so everything here can raise ValueRange -- a
scalar past 255 is caught at the boundary rather than emitted as
mojibake, the same contract DynStr.Bytes states.

Deliberately not here: streams, seeking, formatted output,
directories.  A file is read or written whole, because that is
what every caller in this repository does and a partial-read API
invites the truncation bugs Http.RecvMax already had to fix.

### WriteLine (RO s: STR)

_(documented with the group below)_

### Write (RO s: STR)

_(documented with the group below)_

### WriteI64 (v: I64)

to STDOUT: with a newline, without one, and a decimal integer.
Buffered, and flushed by Halt below -- which is why Halt is the
only way out of a program that has written anything.

  s -- CHARs are Unicode scalars and go out as octets; a scalar
       past 255 is the CHAR/octet boundary and belongs to
       DynStr.Bytes, not here.  Nothing in this module raises,
       so these three cannot be the call that fails.

### ErrLine (RO s: STR)

to STDERR, and flushed.  Diagnostics do not belong in the
program's output stream: the museum's HALT piece is three of
them lost, and a log line interleaved into a data file is the
same accident with a longer fuse.

### ArgCount () : I64

how many command-line arguments there are, the program's own
name INCLUDED as argument 0 -- C's convention, kept because
every caller here is walking argv and an off-by-one at the
boundary is worse than a familiar one.  So a program with no
arguments answers 1, and Arg (pool, 0) is its own name.

### Halt (code: I64)

flushes stdout AND stderr before exiting.  The museum's HALT
piece is here: three diagnostics were lost to an unflushed
buffer, so a halt that does not flush is the bug, and this one
flushes as its first act.  A program that can fail needs an
exit status; it does not need a silent one.

### ParseI64 (RO s: STR) : I64 RAISES ValueRange

decimal, optional leading '-'.  Anything else raises: a command
line is input, and input that is not what it claims is exactly
what the checked-conversion story exists for.

### Run (RO cmd: STR) : I64 RAISES ValueRange

hands one command line to the shell and answers its status.
The shell is what knows how cc is spelled here, so m9c does not
have to.  Quoting is the hazard: a caller composing a path into
a command must refuse what it cannot quote rather than compose
something it cannot predict.

### Env (VAR pool: POOL ; RO name: STR) : STR RAISES ValueRange

the variable's value, or empty when it is unset.  Unset and
empty are not distinguished, because no caller here needs to
and a two-valued answer nobody reads is a trap.

### Exists (RO path: STR) : BOOL RAISES ValueRange

readable?  A probe, not an open: the caller that asks this is
choosing between candidates, and reading each one to find out
would be an answer bought at the price of the question.

### ModTime (RO path: STR) : I64 RAISES ValueRange

when the file was last written, in seconds since the epoch, or
-1 if it cannot be looked at.

A COMPARISON, not a clock.  The only caller asks whether an
object file is older than the source it came from, and for that
the ORDER of two answers is all that matters -- which is why
this is a bare integer rather than a Time.Instant, and why the
resolution being one second is not a defect: a build that
rewrites a source and recompiles it inside the same second is a
build whose inputs nobody could have read either.

### Remove (RO path: STR) : BOOL RAISES ValueRange

deletes a file; answers whether it is gone.  A by-product that
cannot be removed is worth a word, not a raise: the object it
came from was still built.

### ListDir (VAR pool: POOL ; RO path: STR) : SLICE OF STR RAISES IOError, ValueRange

the entries of a directory, '.' and '..' excluded, in the order
the filesystem hands them out -- readdir order, NOT sorted,
because the zarr proxy must answer ?list with the same bytes
the Python reference gets from the same syscall.

  path -- a directory; anything else RAISES IOError carrying
          the path, the same contract as ReadFile.  An EMPTY
          directory answers an empty slice, which is not an
          error: nothing there and nothing readable are
          different answers.

### Arg (VAR pool: POOL ; i: I64) : STR RAISES IndexError, ValueRange

argument i as a fresh string in pool, copied out of the C argv
rather than borrowed from it.

  i -- 0 .. ArgCount - 1, and 0 is the program's own name.
       Anything else RAISES IndexError instead of answering the
       empty string, because an argument that was not given and
       an argument that was given empty are different, and a
       command line is exactly where that difference bites.

### ReadFile (VAR pool: POOL ; RO path: STR) : STR RAISES ValueRange, IOError

the whole file as text, in one allocation.  There is no
seeking and no partial read anywhere in this module, for the
reason the header gives.

  path -- IOError if it cannot be opened or read; the exception
          carries the path, so the caller need not compose the
          message.  ValueRange is the octet boundary on the
          path itself, not on the contents.

For anything large, or anything that is not text, use
ReadFileBytes below and read its note first: a CHAR is four
bytes wide, so this quadruples a file in memory.

### ReadFileBytes (VAR pool: POOL ; RO path: STR) : SLICE OF BYTE RAISES ValueRange, IOError

the same read, as OCTETS.  A CHAR is a Unicode scalar and so
four bytes wide, which is right for text and wrong for a file:
ReadFile on a 207 MB CSV allocates 828 MB and spends a pass
widening bytes nobody wanted widened.  A reader that scans for
commas wants the bytes.  The slice carries one extra zero byte
past the end, so a C string function called on a field inside it
cannot run off the buffer.

### WriteFile (RO path: STR ; RO content: STR) RAISES ValueRange, IOError

_(undocumented)_

### ReadStdin (VAR pool: POOL ; cap: I64) : SLICE OF BYTE

one read(2) from standard input: up to cap bytes, and an EMPTY
slice at end of input.  The whole-file rule above is for files;
a stream has no whole, and a language server frames its own
messages over this.

  cap -- at most this many bytes; zero or negative answers the
         empty slice without reading.

### Flush ()

push buffered output to standard output NOW.  A server writes a
reply and then blocks reading the next request; without this the
reply sits in the buffer and the client waits on the silence.

### FileSize (RO path: STR) : I64 RAISES ValueRange, IOError

how many bytes the file holds, without reading them: the size
probe ReadFileBytes has always made first, exported.  A caller
deciding whether to REDO work -- the field precompute skipping a
file already written at the right size -- needs the size and not
the contents, and reading half a gigabyte to learn a number is
not a probe.

### ReadFileHead (VAR pool: POOL ; RO path: STR ; cap: I64) : SLICE OF BYTE RAISES ValueRange, IOError

the first `cap` bytes, or the whole file if it is shorter.  The
one bounded read in a module of whole-file reads, and it exists
for headers: a 256-byte probe of a half-gigabyte field cache
decides skip-or-recompute without touching the payload.

### MkDir (RO path: STR) RAISES ValueRange, IOError

create the directory, one level, existing is fine -- what an
output directory needs before the first file goes into it.

### Rename (RO from: STR ; RO to: STR) RAISES ValueRange, IOError

rename(2): atomic replace on one filesystem -- write the temp
file, Rename over the target, and a reader never sees a half-
written document.

### WriteFileBytes (RO path: STR ; RO content: SLICE OF BYTE) RAISES ValueRange, IOError

the file's bytes become exactly `content` -- the twin of
ReadFileBytes, which existed while writing stayed text-only.
WriteFile narrows CHAR to octet through DynStr.Bytes, one CHAR
per byte, which is right for text and absurd for a large binary:
writing a 345 MB field cache through it would build 1.4 GB of
CHARs first.  That cache is what forced this.

### EXCEPTION IOError

_(undocumented)_

### PutChars (buf: C.ConstPtr ; n: C.SizeT) [REENTRANT]

CHARs straight out as UTF-8.  Console output is TOTAL: every
Unicode scalar has a UTF-8 encoding, so unlike DynStr.Bytes --
which narrows to octets for the wire and must raise -- there is
nothing here that can fail, and the signature says so.
REENTRANT because the C library's stdout lock makes it so,
which is a fact about glibc, not an assumption.

### ArgC () : C.Int [REENTRANT]

_(documented with the group below)_

### Exit (code: C.Int) [SERIAL]

_(documented with the group below)_

### RunCmd (cmd: C.ConstPtr) : C.Int [SERIAL]

SERIAL: system () forks, and forking from several threads while
the others hold locks is the classic way to deadlock a child.
Stated as a contract rather than assumed away.

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

### ReadWhole (path: C.ConstPtr ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [SERIAL]

cap = 0 asks for the size and touches nothing; SERIAL until the
shim's error path is audited, not asserted

### CMkDir (path: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### CRename (from: C.ConstPtr ; to: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### WriteWhole (path: C.ConstPtr ; buf: C.ConstPtr ; n: C.SizeT) : C.Int [SERIAL]

_(undocumented)_
