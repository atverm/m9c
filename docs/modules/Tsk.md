# Tsk

Tsk is the module of the task-side helpers.  Today it holds one:
Tsk.For, a loop over the indices 0 .. n - 1 on a crew of THREADs,
one static chunk a worker.  TASK comes in stage 1 of
docs/task-plan.md.  Then the loop runs on tasks, under the same
name, and the other helpers join it here.

The loop is the per-core shape of the plan's boids table (7.8x
serial at 10,000 birds on the Mac, 9.1x on ct121).  A program no
longer writes its two monitors by hand.  Alex decided it on
2026-11-01: "Par.For as a library module now, built on THREADs".
He named the module Tsk the same day.  Par was taken: the
LPJ-GUESS port has a module of that name, its parameters.

Tsk holds the scheduling only: the chunk bounds, the start of a
round, the barrier at its end, the stop.  The program keeps the
rest.  M9 has no generics and no untyped pointer, so a library
procedure cannot take "any record" and hand it to a thread.  A
procedure value cannot carry one either: there are no closures.
And a THREAD's target must be a procedure of the module that
starts it.  So the program declares its own job record and puts a
Crew in it.  It starts the workers itself, and its own worker runs
the body.  docs/par-plan.md weighs the other forms.

  TYPE Job = RECORD
    crew : Tsk.Crew ;
    a : SLICE OF F64 ;          (* each worker writes its own chunk *)
  END [SHARABLE] ;

  PROCEDURE Worker (VAR j: Job) =
  VAR s : Tsk.Seat ; i : I64 ;
  BEGIN
    s := Tsk.Join (j.crew) ;
    WHILE Tsk.Next (j.crew, s) DO
      BEGIN
        FOR i := s.lo TO s.hi - 1 DO j.a[i] := ... END
      EXCEPT
      | IndexError : s.failed := TRUE
      END
    END
  END Worker ;

  w := Tsk.Workers (n) ;
  Tsk.Start (j.crew, w) ;
  FOR k := 1 TO w DO THREAD (Worker, j) END ;
  Tsk.For (j.crew, n, 0) ;   (* one round: 0 .. n - 1 *)
  Tsk.For (j.crew, n, 0) ;   (* the same workers again *)
  Tsk.Stop (j.crew)

THREAD's own rules apply, unchanged.  The job record is marked
[SHARABLE]: its author claims the workers write disjoint parts of
it.  Tsk makes the chunks disjoint.  No checker sees a body's
writes stay in its chunk.  A body that writes a[i + 1] breaks the
claim silently.  So write a body that writes element i only, for i
in its chunk.  The checker does refuse two misuses, by THREAD's and
MONITOR's own rules: a job record not marked [SHARABLE], and a
field of the Crew's monitors reached from the program.

A round is one call of For.  Every worker gets one chunk of the
round's n indices, possibly empty.  The op of the round reaches
every worker in its Seat, so one crew can run several loops: the
worker picks its body by s.op.

AN EXCEPTION IN A BODY.  M9 has no exception values, so Tsk cannot
carry one from a worker to the program.  A body that lets an
exception escape its worker stops the program by name, as any
THREAD's does (report par 6).  A body that catches it sets
s.failed.  The next Next reports the failure.  For then raises
Failed, but only after every worker has finished the round.  So no
worker is still writing when the program handles it.  The crew
stays usable: the next For runs a new round.

THE WORKERS MUST ALL START.  For waits for every worker named in
Start.  A program that starts fewer waits forever.  THREAD raises
OutOfMemory when the system refuses a thread.  The program that
catches it must stop instead of calling For.

### TYPE Go

the round open now; 0 before the first

### TYPE Done

chunks of this round finished

### TYPE Crew

Seat is one worker's place in the crew, a local of the worker.

### TYPE Seat

0 .. workers - 1

### EXCEPTION Failed

Failed reports that a body set s.failed in the round just run.
Every worker has finished the round when it is raised.

### Chunk (k, n, workers: I64 ; VAR lo, hi: I64)

Chunk gives worker k of workers its chunk of 0 .. n - 1: the
indices lo .. hi - 1.  The chunks are in worker order, disjoint,
and cover 0 .. n - 1.  Their sizes differ by one at most: the
first n MOD workers get the extra index.  A chunk is empty when
n < workers.  No product is formed, so a large n cannot overflow.
It needs workers > 0 and 0 <= k < workers, and gives an empty
chunk otherwise

### Workers (n: I64) : I64

Workers answers the crew size for a loop of n: the cores this
process may run on (System.Cores), at most n, at least 1

### Start (VAR c: Crew ; workers: I64) RAISES Faults.BadArg

Start sets the crew's size.  It comes before the program starts
its workers, and the program then starts exactly that many.  It
raises Faults.BadArg when workers < 1 or the crew has started
already

### Join (VAR c: Crew) : Seat

Join gives the calling worker its seat, a fresh id.  A worker
calls it once, first

### Next (VAR c: Crew ; VAR s: Seat) : BOOL

Next reports the worker's last chunk finished, failed if
s.failed, then waits for the next round.  It answers TRUE with
s.lo, s.hi, s.op, s.n and s.round set and s.failed clear.  It
answers FALSE after Stop, and the worker returns

### For (VAR c: Crew ; n, op: I64) RAISES Failed, Faults.BadArg

For runs one round: every worker runs its chunk of 0 .. n - 1
with this op.  It returns when every worker has finished.  It
raises Failed when a body set s.failed.  It raises Faults.BadArg
before Start and after Stop, and runs nothing then.  One thread
drives a crew: For and Stop are the program's, never a worker's

### Stop (VAR c: Crew)

Stop ends the workers and waits until every one has left Next.
After it no worker touches the job record
