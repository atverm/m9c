# Sup

Sup is supervision for tasks, as OTP's supervisors are in Erlang
(stage 5 of docs/task-plan.md).  A supervisor watches its children.
A child that fails is started again, by a policy.  A supervisor
whose children fail too often gives up, and raises GaveUp to the
code that runs it: it fails upward.

M9 has no closures and a TASK's target is a procedure of the module
that starts it, as with Tsk.  So Sup holds the board and the policy,
and the program starts its children and writes their loop:

  PROCEDURE Child (VAR j: Job) =
  VAR s : Sup.Seat ;
  BEGIN
    s := Sup.Join (j.board) ;
    WHILE Sup.Run (j.board, s) DO
      BEGIN
        ... fresh state, then the work ... ;
        Sup.Done (j.board, s)
      EXCEPT
      | Refused : Sup.Failed (j.board, s, 'Refused')
      | IndexError : Sup.Crashed (j.board, s, 'IndexError')
      | Overflow : Sup.Crashed (j.board, s, 'Overflow')
      | Poisoned : Sup.Crashed (j.board, s, 'Poisoned')
      END
    END
  END Child ;

  FOR k := 1 TO 4 DO TASK (Child, j) END ;
  Sup.Watch (j.board, 4)        (* returns when all four are Done *)

Run waits for the child's next start and answers FALSE once the
supervisor has stopped.  A start is a turn of the child's loop, and
the child builds its state afresh in it: a restart is from scratch.

TWO KINDS OF FAILURE (Alex, 2026-11-02).  A child that ends by a
checked exception reports Failed, and the policy decides: it is
started again, unless that makes more than maxRestarts restarts in
windowMs, and then the supervisor stops every child and Watch
raises GaveUp.  A child that ends by a bug (IndexError, Overflow,
OutOfMemory, Poisoned: the exceptions outside RAISES) reports
Crashed.  It is started again, DIRTY: a bug is not the policy's to
forgive.  The dirtyMax-th dirty crash of one child stops the
program by name, as an unhandled exception does.  A Poisoned
monitor (report par 6) is one such bug: a child that meets one
crashes dirty, and its restart must not use that monitor again.

ONE FOR ONE OR ALL FOR ONE.  One for one starts the failed child
again.  All for one starts every child again: for children that
share state, which the failure may have left half done.  A running
sibling learns it at its next Asked, which a long-running child
calls at its safe points and then returns to Run.  A child blocked
elsewhere learns it only when it comes back.

A zeroed Board is ready, with the defaults: one for one, 3
restarts in 5,000 ms, 3 dirty crashes.  Policy sets them, before
the first child joins.

### CONST MaxChildren

_(documented with the group below)_

### CONST OneForOne

_(documented with the group below)_

### CONST AllForOne

a child's state on the board

### CONST Waiting

_(undocumented)_

### CONST Running

_(undocumented)_

### CONST Finished

_(undocumented)_

### CONST Failing

_(undocumented)_

### CONST Crashing

_(undocumented)_

### TYPE Board

Policy was called

### TYPE Seat

0 .. MaxChildren - 1

### EXCEPTION GaveUp

GaveUp reports that the children failed more often than the
policy allows.  Every child has been told to stop.

### Policy (VAR b: Board ; policy, maxRestarts, windowMs, dirtyMax: I64) RAISES Faults.BadArg

Policy sets the board's policy: OneForOne or AllForOne, at most
maxRestarts clean restarts in windowMs, and dirtyMax dirty crashes
of one child.  It raises Faults.BadArg for a value out of range,
or once a child has joined.

### Join (VAR b: Board) : Seat RAISES Faults.BadArg

Join gives the calling child its seat.  A child calls it once,
first.  It raises Faults.BadArg past MaxChildren.

### Run (VAR b: Board ; VAR s: Seat) : BOOL

Run waits for the child's next start and answers TRUE then; it
answers FALSE once the supervisor has stopped.  A child's first
start needs no wait.

### Done (VAR b: Board ; RO s: Seat)

Done reports the start finished.  The child goes back to Run.

### Failed (VAR b: Board ; RO s: Seat ; RO why: STR)

Failed reports the start failed by a checked exception, why.

### Crashed (VAR b: Board ; RO s: Seat ; RO why: STR)

Crashed reports the start crashed by a bug, why.  The child's
dirtyMax-th crash stops the program, by name.

### Asked (VAR b: Board ; RO s: Seat) : BOOL

Asked answers whether the supervisor wants the child to start
again (all for one) or to stop: the child returns to Run.

### Watch (VAR b: Board ; children: I64) RAISES GaveUp

Watch supervises until the children have joined and every one is
Done, and then stops them all: their Run answers FALSE.  It
raises GaveUp, after stopping them, when the policy allows no
more restarts.  One task watches a board.

### Restarts (VAR b: Board ; VAR clean, dirty: I64)

Restarts gives the restarts made so far, clean and dirty.
