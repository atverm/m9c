# Tsk

Tsk is the module of the task-side helpers.  Today it holds one:
Tsk.For, a loop over the indices 0 .. n - 1 on a crew of workers,
one static chunk a worker.  The workers are THREADs or TASKs, as
the program starts them: Tsk's monitors are task-aware (stage 4 of
docs/task-plan.md).  A crew of TASKs costs no OS thread a worker,
and its workers park between rounds.  Chan holds the channel.

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
starts it.  So Start cannot start the workers.  The program
declares its own job record and puts a Crew in it.  It starts the
workers itself, then tells Start how many started, and its own
worker runs the body.  docs/par-plan.md weighs the other forms.

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

  started := 0 ;
  FOR k := 1 TO Tsk.Workers (n) DO
    BEGIN
      THREAD (Worker, j) ;
      started := started + 1
    EXCEPT
    | OutOfMemory : Io.ErrLine ('a worker did not start')
    END
  END ;
  Tsk.Start (j.crew, started) ;   (* the workers that run *)
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

START COUNTS THE WORKERS THAT RUN.  For waits for every worker
Start was told of, so Start comes after the THREAD statements, with
the number that succeeded.  THREAD raises OutOfMemory when the
system refuses a thread; the crew is then smaller, and the chunks
are cut for its size.  A worker that joins before Start waits in
Next as any other: its chunk is cut when a round opens.  Until
2026-11-01 Start came first, and a program that started fewer
workers than it named waited for ever (Alex: "why not start them
automatically in Start?"; the rules above say why not, and this
order removes the hang).

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

Start sets the crew's size: the workers the program started.  It
comes after their THREAD statements, before the first For.  It
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
