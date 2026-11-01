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

### Executable (VAR pool: POOL) : UTF RAISES ValueRange

Since 0.26 a call of Executable is ExecutableUtf, whose heading this is.

ExecutableUtf answers the path's bytes validated as UTF-8.
Executable answers them one CHAR a byte, so
`UTF (System.Executable (pool))` would encode a name past ASCII
twice.

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

### Exec (VAR pool: POOL ; RO prog: UTF ; RO args: SLICE OF UTF ; RO input: UTF ; RO env: SLICE OF UTF) : ResultUtf RAISES ValueRange, Io.IOError

Since 0.26 a call of Exec is ExecUtf, whose heading this is.

_(undocumented)_

### ExecWithin (VAR pool: POOL ; RO prog: UTF ; RO args: SLICE OF UTF ; RO input: UTF ; RO env: SLICE OF UTF ; seconds: F64) : ResultUtf RAISES ValueRange, Io.IOError

Since 0.26 a call of ExecWithin is ExecWithinUtf, whose heading this is.

_(undocumented)_

### Become (RO prog: UTF ; RO name: UTF ; RO args: SLICE OF UTF) RAISES ValueRange, Io.IOError

Since 0.26 a call of Become is BecomeUtf, whose heading this is.

_(undocumented)_

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

### Glob (RO pattern: UTF) : SLICE OF UTF RAISES ValueRange

Since 0.26 a call of Glob is GlobUtf, whose heading this is.

_(undocumented)_

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
