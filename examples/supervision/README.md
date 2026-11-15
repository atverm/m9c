# Supervision: workers that fail and are started again

`Supervise.m9` runs three worker tasks under a supervisor. The supervisor
is the library module `Sup`, which lives with the rest of the library in
the repository's [corpus/Sup.m9](../../corpus/Sup.m9), not in this folder;
`m9c` finds it on its library path, as it finds `Io`. This is the stage 5
example of [docs/task-plan.md](../../docs/task-plan.md).

A worker sums the answers a flaky service gives for its ten items. Each
item's first request fails with a checked exception, `Unavailable`. The
worker reports the failure to the supervisor and goes back to `Sup.Run`.
The supervisor then starts it again, and the worker begins its sum from
zero. A restart is from scratch, so the sums printed are clean.

## Run it

    m9c --make -o supervise Supervise.m9
    ./supervise              # every failed start is started again
    ./supervise giveup       # item 7 always fails: the supervisor gives up
    ./supervise dirty        # worker 0 has a bug: the third crash stops the program

The three runs print:

    worker 0 sum 285 starts 11
    worker 1 sum 285 starts 11
    worker 2 sum 285 starts 11
    restarts 30 clean, 0 dirty

    the supervisor gave up after 4 restarts            (exit status 2)

    m9: Sup: child 0 crashed 3 times by a bug, the last by IndexError; the program stops
                                                       (exit status 1)

## The two kinds of failure

- A child that ends by a **checked exception** reports `Sup.Failed`. The
  policy decides: it is started again, unless that makes more than the
  allowed restarts in the window. Then the supervisor stops every child,
  and `Sup.Watch` raises `Sup.GaveUp` to the code that runs it.
- A child that ends by a **bug** (IndexError, Overflow, OutOfMemory,
  Poisoned) reports `Sup.Crashed`. It is started again, marked dirty. Its
  third dirty crash stops the program by name, as an unhandled exception
  does.

A monitor that a bug left half updated is poisoned: every later call into
it raises `Poisoned`, so no one reads the broken state. A child that meets
one crashes dirty too. Its restart gets fresh storage, or the monitor is
rebuilt by a procedure marked `[RESET]`.

The `tasks` gate (`runtime/test/tasks.sh`) holds all three runs, on one
carrier and on every core.
