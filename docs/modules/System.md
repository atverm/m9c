# System

System shows the process, seen from inside: what it was called
with, how big it is and what the machine offers, the pools it is
holding, and other programs run with their output collected.

Nothing here is inferred.  A flag is a flag because the caller
asked for it by name; a pool is listed because the runtime carved
a block for it; a program is run with the arguments given, through
no shell, and both of its streams come back as strings.

### TYPE Memory

this process, bytes: now, and high water

### TYPE PoolInfo

bytes carved, bytes held, blocks

### TYPE ResultUtf

the exit status; minus the signal number
when the program was killed by one

### TYPE Result

Result and ResultUtf are one type since STR is the UTF-8 type
(2026-10-31).  Exec, ExecWithin and their Utf twins answer it.

### EXCEPTION NoPool

_(documented with the group below)_

### Os () : STR

Os answers the platform this program is running on, as a VALUE:
'linux', 'windows', 'macos', or 'posix' for another Unix.  M9 has
no conditional compilation by design.  So a program that must
branch on the platform (a path separator, where a library lives)
asks at run time, and both branches stay in the text where a
reviewer can read them.

### Executable (VAR pool: POOL) : STR RAISES ValueRange

**Deprecated** (the UTF transition): ExecutableUtf is its UTF form.

Executable answers the running executable's resolved path, as the
kernel knows it, or empty when the system will not say.  It is
NOT Program, which is how the program was CALLED and may be a
bare name found on PATH.  This is where the binary IS, which is
what a tool that ships beside its own library needs to find it.
The answer is on Io's path wire, bytes as CHARs, so it can be
handed to Io as it is.

### Cores () : I64

Cores answers the processors this process may run on right
now.

### Mem () : Memory

_(documented with the group below)_

### PoolCount () : I64

PoolCount answers the pools holding at least one block.  A pool
with nothing carved from it costs nothing and is not a pool the
runtime knows.

### PoolAt (i: I64) : PoolInfo RAISES NoPool

PoolAt answers pool i of PoolCount, oldest first.  The runtime
groups its live blocks by the pool that carved them.  So a pool
that leaked, freed with its owner rather than by name, is listed
for what it is: blocks still held.

### PoolBytes () : I64

PoolBytes answers the capacity held by every live pool
together.

### KeepAtMost (bytes: I64)

KeepAtMost caps the large freed blocks the calling thread keeps
for its next carves, 128 MB until it is called.  0 keeps none.  A
THREAD started afterwards starts with the same cap.  So the code
that starts a server's workers decides what they hold between
requests, instead of every worker keeping its largest request
for the life of the process.  M9_BLOCK_REUSE=0 still turns
keeping off for the whole process.

### ReleaseKept ()

ReleaseKept gives the calling thread's kept blocks back now.  The
cap stays.  A worker calls it when it goes idle.

### KeptBytes () : I64

KeptBytes answers the bytes the calling thread keeps in large
blocks now.

### Exec (VAR pool: POOL ; RO prog: STR ; RO args: SLICE OF STR ; RO input: STR ; RO env: SLICE OF STR) : Result RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): ExecUtf is its UTF form.

Exec runs prog with args directly, with no shell, so an argument
is an argument and not a command.  It feeds it `input` on stdin
(the empty string is an immediate end-of-file, never this
program's own stdin), waits for it, and collects both streams
whole.  `env` is NAME=VALUE overrides MERGED over the inherited
environment: [ 'LC_ALL=C' ] pins one variable and keeps the
rest, so PATH still finds the program.  Pass no input and no env
with '' and an empty slice.  Exec raises IOError when the program
could not be started at all (not found, not executable); a
program that starts and fails answers with its status.  stdin
and both streams are pumped together, so a large input and a
large output do not deadlock.  It waits as long as the program
takes: ExecWithin is the one that does not.

### ExecWithin (VAR pool: POOL ; RO prog: STR ; RO args: SLICE OF STR ; RO input: STR ; RO env: SLICE OF STR ; seconds: F64) : Result RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): ExecWithinUtf is its UTF form.

ExecWithin is Exec with a deadline over the whole run: starting
it, both streams, and its exit.  When the time is up the program
AND EVERYTHING IT STARTED are killed (its own process group on
POSIX, a job object on Windows), and `stopped` answers TRUE.
`out` and `err` still hold what the program had written by
then: a bounded run reports, it does not vanish.

The children matter as much as the child.  A program that has
exited while something it started still holds its stdout is the
case that waits forever without this, because the wait is on the
STREAMS ending and not on the exit.

`seconds` not greater than zero is no limit at all, which is
exactly Exec.  A bounded run is put in a group of its own so
that it can be killed whole.  A group of its own no longer
receives the terminal's Ctrl-C.  That is the price of the bound,
and it is why an unbounded run is not given one.

### Become (RO prog: STR ; RO name: STR ; RO args: SLICE OF STR) RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): BecomeUtf is its UTF form.

THIS PROCESS BECOMES prog, told `name` as its argv[0] and args
after it.  It keeps this process's stdin, stdout, stderr,
environment and terminal, its exit status is the exit status, and
a Ctrl-C reaches it as if it had been started by hand.  Exec,
collecting both streams, is not that.  Nothing after a successful
Become runs.  Become raises IOError when prog could not be
started, and then this process is still here to say so.  POSIX
replaces the process (execv); Windows, which cannot, starts prog
with this process's handles, waits, and exits with its
status.

### ProcessId () : I64

ProcessId answers this process's id: a name no other process
running at the same moment holds.

### Program (VAR pool: POOL) : STR RAISES ValueRange, IndexError

Program answers argv[0]: how this program was invoked.

### Args (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

Args answers the arguments after the program name, all of them,
in order.

### Flag (RO name: STR) : BOOL RAISES ValueRange, IndexError

Flag asks whether the word `name` (say `--verbose`) is among the
options.

### Value (RO name: STR ; RO dflt: STR) : STR RAISES ValueRange, IndexError

Value answers the text after `name=` in the first option that
carries it, else dflt: Value (pool, '--out', 'a.nc').

### Positional (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

Positional answers every argument that is not an option, in
order.

### Glob (RO pattern: STR) : SLICE OF STR RAISES ValueRange

**Deprecated** (the UTF transition): GlobUtf is its UTF form.

see GlobUtf below for the UTF form

### ExecUtf (VAR pool: POOL ; RO prog: UTF ; RO args: SLICE OF UTF ; RO input: UTF ; RO env: SLICE OF UTF) : ResultUtf RAISES ValueRange, Io.IOError

_(undocumented)_

### ExecWithinUtf (VAR pool: POOL ; RO prog: UTF ; RO args: SLICE OF UTF ; RO input: UTF ; RO env: SLICE OF UTF ; seconds: F64) : ResultUtf RAISES ValueRange, Io.IOError

_(undocumented)_

### BecomeUtf (RO prog: UTF ; RO name: UTF ; RO args: SLICE OF UTF) RAISES ValueRange, Io.IOError

_(documented with the group below)_

### ExecutableUtf (VAR pool: POOL) : UTF RAISES ValueRange

ExecutableUtf answers the path's bytes validated as UTF-8.
Executable answers them one CHAR a byte, so
`UTF (System.Executable (pool))` would encode a name past ASCII
twice.

### GlobUtf (RO pattern: UTF) : SLICE OF UTF RAISES ValueRange

_(undocumented)_

### NCpu () : C.Int [REENTRANT]

_(documented with the group below)_

### OsCode () : C.Int [REENTRANT]

OsCode answers 1 linux, 2 windows, 3 macos, 0 another POSIX; Os
spells them.

### ExePath (buf: C.MutPtr ; cap: C.Int) : C.Int [REENTRANT]

ExePath writes the executable's path as bytes into buf and
answers its length, or -1 when the system will not say.

### MemInfo (buf: C.MutPtr) [REENTRANT]

MemInfo writes four int64 into buf: resident, peak, total,
available.

### KeepAtMostC (bytes: C.SSizeT) [REENTRANT]

_(documented with the group below)_

### ReleaseKeptC () [REENTRANT]

_(documented with the group below)_

### KeptBytesC () : C.SSizeT [REENTRANT]

These three act on the calling thread's own kept blocks.  The
blocks are thread-local, so the calls need no lock.

### PoolN () : C.SSizeT [REENTRANT]

_(documented with the group below)_

### PoolI (i: C.SSizeT ; buf: C.MutPtr) : C.Int [REENTRANT]

PoolI writes three int64 into buf: used, capacity, blocks.  It
answers 0 when i is out of range.  Both take the registry's own
lock.

### ExecStart (argv: C.ConstPtr ; n: C.Int ; input: C.ConstPtr ; inlen: C.SSizeT ; env: C.ConstPtr ; envn: C.Int ; limitMs: C.SSizeT) : C.Int [REENTRANT]

ExecStart takes n NUL-terminated UTF-8 strings back to back, the
program first, and inlen bytes of stdin (0 = an immediate EOF).
It takes envn NUL-terminated NAME=VALUE strings, each merged over
the inherited environment.  limitMs is milliseconds for the whole
run, after which the child and its children are killed (0 or
less: no limit, and then nothing is done differently).  ExecStart
answers a handle, or -1 when it could not start.  The slot table
is under its own lock, so two threads may run programs at
once.

### ExecStatus (h: C.Int) : C.Int [REENTRANT]

_(documented with the group below)_

### ExecStopped (h: C.Int) : C.Int [REENTRANT]

ExecStopped answers 1 when the limit ran out and the run was
killed.

### ExecLen (h: C.Int ; which: C.Int) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecCopy (h: C.Int ; which: C.Int ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecRelease (h: C.Int) [REENTRANT]

_(documented with the group below)_

### BecomeC (prog: C.ConstPtr ; argv: C.ConstPtr ; n: C.Int) : C.Int [REENTRANT]

BecomeC takes prog NUL-terminated, and n strings back to back,
argv[0] first.  It answers only when prog could not be started:
-1.

### Pid () : C.SSizeT [REENTRANT]

_(undocumented)_
