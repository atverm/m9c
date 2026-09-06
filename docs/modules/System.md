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

### EXCEPTION NoPool

_(documented with the group below)_

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
a large input and a large output do not deadlock.

### Program (VAR pool: POOL) : STR RAISES ValueRange, IndexError

argv[0]: how this program was invoked

### Args (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

the arguments after the program name, all of them, in order

### Flag (RO name: STR) : BOOL RAISES ValueRange, IndexError

is the word `name` (say `--verbose`) among the options

### Value (VAR pool: POOL ; RO name: STR ; RO dflt: STR) : STR RAISES ValueRange, IndexError

the text after `name=` in the first option that carries it, else
dflt: Value (pool, '--out', 'a.nc')

### Positional (VAR pool: POOL) : SLICE OF STR RAISES ValueRange, IndexError

every argument that is not an option, in order

### NCpu () : C.Int [REENTRANT]

_(documented with the group below)_

### MemInfo (buf: C.MutPtr) [REENTRANT]

four int64 into buf: resident, peak, total, available

### PoolN () : C.SSizeT [REENTRANT]

_(documented with the group below)_

### PoolI (i: C.SSizeT ; buf: C.MutPtr) : C.Int [REENTRANT]

three int64 into buf: used, capacity, blocks; 0 when i is out of
range.  Both take the registry's own lock.

### ExecStart (argv: C.ConstPtr ; n: C.Int ; input: C.ConstPtr ; inlen: C.SSizeT ; env: C.ConstPtr ; envn: C.Int) : C.Int [REENTRANT]

n NUL-terminated UTF-8 strings back to back, the program first;
inlen bytes of stdin (0 = an immediate EOF); envn NUL-terminated
NAME=VALUE strings, each merged over the inherited environment.
Answers a handle, or -1 when it could not start.  The slot table
is under its own lock, so two threads may run programs at once.

### ExecStatus (h: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### ExecLen (h: C.Int ; which: C.Int) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecCopy (h: C.Int ; which: C.Int ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### ExecRelease (h: C.Int) [REENTRANT]

_(undocumented)_
