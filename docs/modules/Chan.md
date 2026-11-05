# Chan

Chan is the channel between tasks (stage 4 of docs/task-plan.md): a
bounded ring in a monitor.  Send waits while the ring is full and
Receive while it is empty.  A task that waits parks, and its
carrier runs other tasks.  A THREAD waits in its own way, so a
channel joins THREADs and TASKs alike.

A channel carries I64s (Alex, 2026-11-02: "I64 + index").  M9 has
no generics, so one element type is chosen, and the index is the
one that carries anything.  A bigger message stays in the
program's own [SHARABLE] table, and the channel carries its index:
job k, chunk k, agent k.  Ownership stays checked: the table is
the program's, and the claim that each index is in one hand at a
time is the program's, as for any [SHARABLE] record.

  TYPE Job = RECORD
    work : Chan.Ints ;           (* the indices of the chunks to do *)
    done : Chan.Ints ;           (* the indices done *)
    chunks : SLICE OF Chunk ;    (* the messages themselves *)
  END [SHARABLE] ;

  PROCEDURE Worker (VAR j: Job) =
  VAR k : I64 ;
  BEGIN
    WHILE Chan.Receive (j.work, k) DO
      ... j.chunks[k] ... ;
      Chan.Send (j.done, k)
    END
  END Worker ;

CLOSE ends a channel's sending.  Receive drains what is in the
ring, then answers FALSE: that is how a worker learns there is no
more work.  Send on a closed channel raises Closed.  Close twice is
no error.

A zeroed Ints is ready, with room for MaxCap values.  SetCap makes
the ring smaller, before the first Send.  A smaller ring makes a
fast sender wait for a slow receiver sooner: that is the
back-pressure a pipeline wants.  There is no unbuffered channel.
SetCap (c, 1) is the nearest: the sender may run one value ahead.

SIGNAL wakes every waiter of a monitor (report par 6).  So a Send
wakes the receivers waiting, and the senders too, when there are
any.  Each one looks and waits again if there is nothing for it.
Under TASK a wake is a queue push, no system call.  A channel with
thousands of waiters on one side still pays for each look.

### CONST MaxCap

_(undocumented)_

### TYPE Ints

the oldest value

### EXCEPTION Closed

Closed reports a Send on a channel that was closed.

### SetCap (VAR c: Ints ; cap: I64) RAISES ValueRange

SetCap sets the ring's room, 1 .. MaxCap, while the channel is
empty.  It raises ValueRange for a cap outside that, or when a
value is in the ring.

### Send (VAR c: Ints ; v: I64) RAISES Closed

Send puts v in the ring, waiting while it is full.  It raises
Closed when the channel was closed, also while it waited.

### Receive (VAR c: Ints ; VAR v: I64) : BOOL

Receive takes the oldest value into v, waiting while the ring is
empty.  It answers FALSE, and leaves v, when the channel is
closed and the ring empty.

### TrySend (VAR c: Ints ; v: I64) : BOOL RAISES Closed

TrySend puts v in the ring if there is room, and answers whether
it did.  It never waits.  It raises Closed as Send does.

### TryReceive (VAR c: Ints ; VAR v: I64) : BOOL

TryReceive takes the oldest value into v if there is one, and
answers whether it did.  It never waits.

### Close (VAR c: Ints)

Close ends the sending and wakes every waiter.

### Count (VAR c: Ints) : I64

Count answers the values in the ring now.
