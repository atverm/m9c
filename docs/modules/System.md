# System

The process, seen from inside: what it was called with, how big it
is and what the machine offers, the pools it is holding, and other
programs run with their output collected.

Nothing here is inferred.  A flag is a flag because the caller
asked for it by name; a pool is listed because the runtime carved
a block for it; a program is run with the arguments given, through
no shell, and both of its streams come back as strings.

### TYPE Memory

this process, bytes: now, and high water

### TYPE PoolInfo

bytes carved, bytes held, blocks

### TYPE Result

the exit status; minus the signal number
when the program was killed by one

### TYPE ResultUtf

the streams as the UTF-8 they are

### EXCEPTION NoPool

_(documented with the group below)_

### Os () : STR

the platform this program is running on, as a VALUE: 'linux',
'windows', 'macos', or 'posix' for another Unix.  M9 has no
conditional compilation by design, so a program that must branch
on the platform -- a path separator, where a library lives --
asks at run time and both branches stay in the text where a
reviewer can read them.

### Executable (VAR pool: POOL) : STR RAISES ValueRange

**Deprecated** (the UTF transition): ExecutableUtf is its UTF form.

the running executable's resolved path, as the kernel knows it,
or empty when the system will not say.  NOT Program, which is
how the program was CALLED and may be a bare name found on PATH:
this is where the binary IS, which is what a tool that ships
beside its own library needs to find it.  On Io's path wire,
bytes as CHARs, so the answer can be handed to Io as it is.

### Cores () : I64

processors this process may run on right now

### Mem () : Memory

_(documented with the group below)_

### PoolCount () : I64

pools holding at least one block.  A pool with nothing carved
from it costs nothing and is not a pool the runtime knows.

### PoolAt (i: I64) : PoolInfo RAISES NoPool

pool i of PoolCount, oldest first.  The runtime groups its live
blocks by the pool that carved them, so a pool that leaked --
freed with its owner rather than by name -- is listed for what
it is: blocks still held.

### PoolBytes () : I64

capacity held by every live pool together

### Exec (VAR pool: POOL ; RO prog: STR ; RO args: SLICE OF STR ; RO input: STR ; RO env: SLICE OF STR) : Result RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): ExecUtf is its UTF form.

run prog with args -- directly, no shell, so an argument is an
argument and not a command -- feed it `input` on stdin (the
empty string is an immediate end-of-file, never this program's
own stdin), wait for it, and collect both streams whole.  `env`
is NAME=VALUE overrides MERGED over the inherited environment:
[ 'LC_ALL=C' ] pins one variable and keeps the rest, so PATH
still finds the program.  Pass no input and no env with '' and an
empty slice.  IOError when it could not be started at all (not
found, not executable); a program that starts and fails answers
with its status.  stdin and both streams are pumped together, so
a large input and a large output do not deadlock.  It waits as
long as the program takes: ExecWithin is the one that does not.

### ExecWithin (VAR pool: POOL ; RO prog: STR ; RO args: SLICE OF STR ; RO input: STR ; RO env: SLICE OF STR ; seconds: F64) : Result RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): ExecWithinUtf is its UTF form.

Exec, with a deadline over the whole run -- starting it, both
streams, and its exit.  When the time is up the program AND
EVERYTHING IT STARTED are killed (its own process group on
POSIX, a job object on Windows), `stopped` answers TRUE, and
what the program had written by then is still in `out` and
`err`: a bounded run reports, it does not vanish.

The children matter as much as the child.  A program that has
exited while something it started still holds its stdout is the
case that waits forever without this, because what is waited on
is the STREAMS ending and not the exit.

`seconds` not greater than zero is no limit at all, which is
exactly Exec.  A bounded run is put in a group of its own so
that it can be killed whole, and a group of its own no longer
receives the terminal's Ctrl-C: that is the price of the bound,
and it is why an unbounded run is not given one.

### Become (RO prog: STR ; RO name: STR ; RO args: SLICE OF STR) RAISES ValueRange, Io.IOError

**Deprecated** (the UTF transition): BecomeUtf is its UTF form.

THIS PROCESS BECOMES prog, told `name` as its argv[0] and args
after it.  It keeps this process's stdin, stdout, stderr,
environment and terminal, its exit status is the exit status, and
a Ctrl-C reaches it as if it had been started by hand -- which is
what Exec, collecting both streams, is not.  Nothing after a
successful Become runs; IOError when prog could not be started,
and then this process is still here to say so.  POSIX replaces
the process (execv); Windows, which cannot, starts prog with this
process's handles, waits, and exits with its status.

### ProcessId () : I64

this process's id: a name no other process running at the same
moment holds

### Program (VAR pool: POOL) : STR RAISES ValueRange, IndexError

argv[0]: how this program was invoked

### Args (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

the arguments after the program name, all of them, in order

### Flag (RO name: STR) : BOOL RAISES ValueRange, IndexError

is the word `name` (say `--verbose`) among the options

### Value (RO name: STR ; RO dflt: STR) : STR RAISES ValueRange, IndexError

the text after `name=` in the first option that carries it, else
dflt: Value (pool, '--out', 'a.nc')

### Positional (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

every argument that is not an option, in order

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

the path's bytes validated as UTF-8 -- Executable answers them one
CHAR a byte, so `UTF (System.Executable (pool))` would encode a
name past ASCII twice

### GlobUtf (RO pattern: UTF) : SLICE OF UTF RAISES ValueRange

_(undocumented)_

### NCpu () : C.Int [REENTRANT]

_(documented with the group below)_

### OsCode () : C.Int [REENTRANT]

1 linux, 2 windows, 3 macos, 0 another POSIX; Os spells them

### ExePath (buf: C.MutPtr ; cap: C.Int) : C.Int [REENTRANT]

the executable's path as bytes into buf, its length; -1 when the
system will not say

### MemInfo (buf: C.MutPtr) [REENTRANT]

four int64 into buf: resident, peak, total, available

### PoolN () : C.SSizeT [REENTRANT]

_(documented with the group below)_

### PoolI (i: C.SSizeT ; buf: C.MutPtr) : C.Int [REENTRANT]

three int64 into buf: used, capacity, blocks; 0 when i is out of
range.  Both take the registry's own lock.

### ExecStart (argv: C.ConstPtr ; n: C.Int ; input: C.ConstPtr ; inlen: C.SSizeT ; env: C.ConstPtr ; envn: C.Int ; limitMs: C.SSizeT) : C.Int [REENTRANT]

n NUL-terminated UTF-8 strings back to back, the program first;
inlen bytes of stdin (0 = an immediate EOF); envn NUL-terminated
NAME=VALUE strings, each merged over the inherited environment;
limitMs milliseconds for the whole run, after which the child
and its children are killed (0 or less: no limit, and then
nothing is done differently).  Answers a handle, or -1 when it
could not start.  The slot table is under its own lock, so two
threads may run programs at once.

### ExecStatus (h: C.Int) : C.Int [REENTRANT]

_(documented with the group below)_

### ExecStopped (h: C.Int) : C.Int [REENTRANT]

1 when the limit ran out and the run was killed

### ExecLen (h: C.Int ; which: C.Int) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecCopy (h: C.Int ; which: C.Int ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecRelease (h: C.Int) [REENTRANT]

_(documented with the group below)_

### BecomeC (prog: C.ConstPtr ; argv: C.ConstPtr ; n: C.Int) : C.Int [REENTRANT]

prog NUL-terminated; n strings back to back, argv[0] first.
Answers only when prog could not be started: -1

### Pid () : C.SSizeT [REENTRANT]

_(undocumented)_
