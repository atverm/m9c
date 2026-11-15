# Traffic: tasks in simulated time

`Traffic.m9` is a ring road of 50 segments with a car per task. It is the
stage 4 example of [docs/task-plan.md](../../docs/task-plan.md), and shows
the three things `TASK` is for in one program:

- **A task per car that sleeps in simulated time.** A car drives a trip of
  a few segments at the speed its segment allows, stops for a while, and
  drives again. Between moves it sleeps until its tick comes.
- **A master that owns the clock.** The module body moves to the next tick
  only when every car due at this one has moved and is asleep again. So
  every car sees the state of the tick before, and the run is the same
  whatever the scheduler does.
- **A parallel step after each tick.** `Tsk.For`, on a crew of tasks,
  gives each car its speed from how full its segment is.

A car that arrives sends its number and its trip time through a
`Chan.Ints` to a logger task. The logger's sums do not depend on the order
the arrivals come in.

## Run it

    m9c --make -o traffic Traffic.m9
    ./traffic                  # 400 cars, 1,000 ticks
    ./traffic 2000 500         # 2,000 cars, 500 ticks

It prints the arrivals, the summed trip times and a checksum:

    cars 400 ticks 1000 arrivals 21231 trip ticks 333579 check 133748114

`M9_CARRIERS=1 ./traffic` must print the same line. The `tasks` gate
(`runtime/test/tasks.sh`) holds both settings to these numbers, on one
carrier and on every core.

## Why the clock is 64 monitors

`SIGNAL` wakes every waiter of a monitor. With one clock monitor, each tick
woke every car, and every car competed for the one lock to look at its
tick. A car now sleeps in the bucket of its wake tick modulo 64, so a tick
wakes only the cars due at it. A separate monitor counts the cars still
moving.

| 2,000 cars, 500 ticks (M4) | one carrier | every core |
|---|---:|---:|
| one clock monitor | 0.29 s | 2.85 s |
| 64 bucket monitors | 0.05 s | 0.32 s |

A car does almost nothing between two sleeps, so a wake on another carrier
costs more than the work it starts. For this load, one carrier is the
faster.
