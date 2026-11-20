# Jobs

Jobs is a board of work for a crew of workers, THREADs or TASKs.
A job is a number: a row's key, an index into the program's own
table (as with Chan, "I64 + index").  The board keeps the jobs
that wait, in order, and the jobs that workers hold.  A worker
that fails gives its job back.  The job goes to the back of the
line and the board counts its failures.  So the board does what a supervisor's mailbox and queue do
in an actor program, in one monitor and with no message that can
be lost (docs/agent-ergonomics-plan.md, step 1).

M9 has no closures, so the program starts its workers and writes
their loop, as with Sup:

  PROCEDURE Worker (VAR c: Crew) =
  VAR id : I64 ;
  BEGIN
    id := 0 ;
    LOOP
      BEGIN
        ... fresh state ... ;
        WHILE Jobs.Take (c.board, id) DO
          ... the work on job id ... ;
          Jobs.Done (c.board, id)
        END ;
        EXIT
      EXCEPT
      | Refused : Jobs.GiveBack (c.board, id)
      END
    END
  END Worker ;

A turn of the outer loop is a restart: the worker builds its state
afresh and takes the next job of the line.

A JOB THAT FAILS EVERY TIME.  A job given back waits behind the
others, so one bad job does not hold a worker while good ones
wait.  It still comes round again, for ever, unless the worker
ends it.  Failed answers how often the job a worker holds was
given back, and the worker decides:

  WHILE Jobs.Take (c.board, id) DO
    IF Jobs.Failed (c.board, id) >= 5 THEN
      ... record the job as refused, in the program's store ...
    ELSE
      ... the work on job id ...
    END ;
    Jobs.Done (c.board, id)
  END

Until 2026-11-20 a job given back went to the FRONT.  In a blind
trial six batches that PostgreSQL refused every time were taken
again at once, and held all six workers for ever.

EACH JOB ONCE.  Add ignores a job that waits or is held.  So two
sources may add the same job: the request that made it, and a scan
of the store that looks for work left by an earlier run.  A job
that is Done is forgotten, and adding it again queues it again.
So the scan asks the store for the jobs still to do.  A job may be
finished between the scan's read and its Add, and is then taken
once more: the work must see in the store that nothing is left to
do.

A zeroed Board is ready.  It holds MaxWaiting jobs that wait and
MaxHeld that are held.  Add drops a job when the board is full.
The job is still in the program's store, and a later scan adds it.

### CONST MaxWaiting

_(undocumented)_

### CONST MaxHeld

_(undocumented)_

### TYPE Board

the jobs that wait, a ring

### Add (VAR b: Board ; id: I64)

Add puts the job at the back of the line.  It does nothing when
the job waits or is held already, when the board is full, or
when it is closed.  It never waits.

### Take (VAR b: Board ; VAR id: I64) : BOOL

Take gives the calling worker the job at the front, and the board
holds it for the worker.  It waits while no job waits or MaxHeld
are held.  It answers FALSE, and leaves id, once the board is
closed.

### Done (VAR b: Board ; id: I64)

Done reports the job finished.  The board forgets it.  A job that
is not held is ignored.

### GiveBack (VAR b: Board ; id: I64)

GiveBack reports that the worker failed with the job.  The job
goes to the BACK of the line, also when the line is full: a job
held is never dropped.  Its count of failures goes up by one.  A
job that is not held is ignored.

### Failed (VAR b: Board ; id: I64) : I64

Failed answers how often the job was given back, for a job a
worker holds: 0 the first time it is taken.  It answers 0 for a
job that is not held.  Done forgets the count, so a job added
again starts at 0.

### Close (VAR b: Board)

Close ends the work.  Every Take answers FALSE from then on.

### Waiting (VAR b: Board) : I64

Waiting answers the jobs in the line now.

### Held (VAR b: Board) : I64

Held answers the jobs workers hold now.

### GivenBack (VAR b: Board) : I64

GivenBack answers how many times a job was given back: the
crew's restarts.
