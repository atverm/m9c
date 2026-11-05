/* task_driver.c holds TASK's runtime (m9rt.c, the TASK section) to
   stage 1 of docs/task-plan.md, before any language change:
     Ten tasks each add 1,000 to a monitor's count, yielding between
     adds.  The total is exact, and main sees it after one WAIT.
     Two tasks hand a turn back and forth 100,000 times through one
     monitor.  The time per round trip is printed.
     100,000 tasks park in WAIT on one monitor and one SIGNAL frees
     them.  Every one counts itself out, exactly once.
     A THREAD waits for a task's SIGNAL, and a task waits for a
     THREAD's.  Both directions end.
     A task holds monitor A while it waits in B.  Another task that
     enters A parks until the first leaves A.  It does not stop the
     carrier, and the re-entry check does not fire.
     A THREAD that starts tasks and returns waits for them.
     A program whose every task waits stops by name ("every task
     waits"), in a child.  A task that recurses without end stops by
     name ("task stack overflow in Deep"), in a child.  Each child's
     stderr is read and its exit is by signal. */
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>
#include <pthread.h>
#include "m9rt.h"

static int bad = 0, checks = 0;
static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { bad++; printf ("FAIL %s\n", what); }
  else printf ("ok   %s\n", what);
}

static double now (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* ---- 1. counts ---- */

typedef struct { m9_mon m; int64_t count; int done; } Tally;
static Tally tally;

static void *adder (void *arg, m9_pool *pool)
{
  Tally *t = arg;
  int i;
  (void) pool;
  for (i = 0; i < 1000; i++) {
    m9_mon_enter (&t->m);
    t->count++;
    m9_mon_leave (&t->m);
    m9_task_yield ();
  }
  m9_mon_enter (&t->m);
  t->done++;
  m9_mon_signal (&t->m);
  m9_mon_leave (&t->m);
  return NULL;
}

static void counts (void)
{
  m9_state err;
  int i;
  memset (&err, 0, sizeof err);
  for (i = 0; i < 10; i++) m9_task_start2 (adder, &tally, NULL, "adder", &err);
  m9_mon_enter (&tally.m);
  while (tally.done < 10) m9_mon_wait (&tally.m);
  m9_mon_leave (&tally.m);
  ok ("ten tasks add 1,000 each: 10,000", tally.count == 10000);
}

/* ---- 2. ping-pong ---- */

#define ROUNDS 100000
typedef struct { m9_mon m; int turn; int ended; } Ball;
static Ball ball;

static void *player (void *arg, m9_pool *pool)
{
  int me = (int) (intptr_t) arg;
  int i;
  (void) pool;
  for (i = 0; i < ROUNDS; i++) {
    m9_mon_enter (&ball.m);
    while (ball.turn != me) m9_mon_wait (&ball.m);
    ball.turn = 1 - me;
    m9_mon_signal (&ball.m);
    m9_mon_leave (&ball.m);
  }
  m9_mon_enter (&ball.m);
  ball.ended++;
  m9_mon_signal (&ball.m);
  m9_mon_leave (&ball.m);
  return NULL;
}

static void pingpong (void)
{
  m9_state err;
  double t0, t1;
  memset (&err, 0, sizeof err);
  t0 = now ();
  m9_task_start2 (player, (void *) (intptr_t) 0, NULL, "ping", &err);
  m9_task_start2 (player, (void *) (intptr_t) 1, NULL, "pong", &err);
  m9_mon_enter (&ball.m);
  while (ball.ended < 2) m9_mon_wait (&ball.m);
  m9_mon_leave (&ball.m);
  t1 = now ();
  ok ("two tasks pass the turn 100,000 times each", ball.ended == 2 && ball.turn == 0);
  printf ("     pingpong: %.3f us per round trip (TASK, one carrier)\n", (t1 - t0) / ROUNDS * 1e6);
}

/* ---- 3. 100,000 parked ---- */

#define PARKED 100000
typedef struct { m9_mon m; int go; int64_t parked; int64_t out; } Gate;
static Gate gate;

static void *parker (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&gate.m);
  gate.parked++;
  m9_mon_signal (&gate.m);
  while (!gate.go) m9_mon_wait (&gate.m);
  gate.out++;
  m9_mon_signal (&gate.m);
  m9_mon_leave (&gate.m);
  return NULL;
}

static void parked (void)
{
  m9_state err;
  int i, fails = 0;
  double t0, t1, t2;
  memset (&err, 0, sizeof err);
  t0 = now ();
  for (i = 0; i < PARKED; i++)
    if (m9_task_start2 (parker, NULL, NULL, "parker", &err) != 0) fails++;
  m9_mon_enter (&gate.m);
  while (gate.parked < PARKED - fails) m9_mon_wait (&gate.m);
  t1 = now ();
  gate.go = 1;
  m9_mon_signal (&gate.m);
  while (gate.out < PARKED - fails) m9_mon_wait (&gate.m);
  m9_mon_leave (&gate.m);
  t2 = now ();
  ok ("100,000 tasks start", fails == 0);
  ok ("100,000 tasks park in WAIT", gate.parked == PARKED);
  ok ("one SIGNAL frees all 100,000, each counted once", gate.out == PARKED);
  printf ("     parked: %.0f ms to start and park, %.0f ms to free (%.2f us per task)\n",
          (t1 - t0) * 1e3, (t2 - t1) * 1e3, (t2 - t0) / PARKED * 1e6);
}

/* ---- 4. a THREAD and a TASK share a monitor ---- */

typedef struct { m9_mon m; int to_thread; int to_task; int thread_saw; int task_saw; } Mix;
static Mix mix;

static void *mix_thread (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&mix.m);
  while (!mix.to_thread) m9_mon_wait (&mix.m);     /* a TASK signals this */
  mix.thread_saw = 1;
  usleep (20000);                                   /* the task is parked by now */
  mix.to_task = 1;
  m9_mon_signal (&mix.m);
  m9_mon_leave (&mix.m);
  return NULL;
}

static void *mix_task (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&mix.m);
  mix.to_thread = 1;
  m9_mon_signal (&mix.m);
  while (!mix.to_task) m9_mon_wait (&mix.m);       /* a THREAD signals this */
  mix.task_saw = 1;
  m9_mon_signal (&mix.m);
  m9_mon_leave (&mix.m);
  return NULL;
}

static void mixed (void)
{
  m9_state err;
  memset (&err, 0, sizeof err);
  m9_thread_start2 (mix_thread, NULL, NULL, &err);
  m9_task_start2 (mix_task, NULL, NULL, "mix_task", &err);
  m9_mon_enter (&mix.m);
  while (!mix.task_saw) m9_mon_wait (&mix.m);
  m9_mon_leave (&mix.m);
  ok ("a THREAD wakes on a TASK's SIGNAL", mix.thread_saw == 1);
  ok ("a TASK wakes on a THREAD's SIGNAL", mix.task_saw == 1);
}

/* ---- 5. a task waits in B while it holds A ---- */

typedef struct { m9_mon m; int v; } Cell;
static Cell ca, cb;
static int a_released, entrant_saw, entrant_done, holding;

static void *holder (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&ca.m);
  m9_mon_enter (&cb.m);
  __atomic_store_n (&holding, 1, __ATOMIC_RELEASE);   /* B is released only in the WAIT */
  while (!cb.v) m9_mon_wait (&cb.m);   /* holds A, parks in B */
  m9_mon_leave (&cb.m);
  a_released = 1;
  m9_mon_leave (&ca.m);
  return NULL;
}

static void *entrant (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&cb.m);
  cb.v = 1;
  m9_mon_signal (&cb.m);
  m9_mon_leave (&cb.m);
  m9_mon_enter (&ca.m);         /* parks until holder leaves A */
  entrant_saw = a_released;
  m9_mon_leave (&ca.m);
  __atomic_store_n (&entrant_done, 1, __ATOMIC_RELEASE);
  return NULL;
}

static void nested (void)
{
  m9_state err;
  memset (&err, 0, sizeof err);
  m9_task_start2 (holder, NULL, NULL, "holder", &err);
  while (!__atomic_load_n (&holding, __ATOMIC_ACQUIRE)) m9_task_yield ();
  m9_task_start2 (entrant, NULL, NULL, "entrant", &err);
  while (!__atomic_load_n (&entrant_done, __ATOMIC_ACQUIRE)) m9_task_yield ();
  ok ("an entrant gets a monitor only after the task waiting while it held it leaves",
      entrant_saw == 1);
}

/* ---- 5b. tasks run on more than one carrier ---- */

#define SPREAD 64
static pthread_t spread_on[SPREAD];
typedef struct { m9_mon m; int done; } Spread;
static Spread spread;

static void *spreader (void *arg, m9_pool *pool)
{
  volatile double x = 0;
  long i;
  (void) pool;
  for (i = 0; i < 2000000; i++) x += (double) i * 1e-9;
  if (x < 0) printf ("never\n");
  spread_on[(intptr_t) arg] = pthread_self ();
  m9_mon_enter (&spread.m);
  spread.done++;
  m9_mon_signal (&spread.m);
  m9_mon_leave (&spread.m);
  return NULL;
}

static void spreads (void)
{
  m9_state err;
  intptr_t i;
  int j, distinct = 0;
  const char *e = getenv ("M9_CARRIERS");
  memset (&err, 0, sizeof err);
  for (i = 0; i < SPREAD; i++) m9_task_start2 (spreader, (void *) i, NULL, "spreader", &err);
  m9_mon_enter (&spread.m);
  while (spread.done < SPREAD) m9_mon_wait (&spread.m);
  m9_mon_leave (&spread.m);
  for (i = 0; i < SPREAD; i++) {
    for (j = 0; j < i; j++) if (pthread_equal (spread_on[i], spread_on[j])) break;
    if (j == i) distinct++;
  }
  if (e != NULL && atoi (e) == 1)
    ok ("M9_CARRIERS=1 runs every task on one carrier", distinct == 1);
  else {
    ok ("64 busy tasks run on more than one carrier", distinct > 1);
    printf ("     spread: 64 tasks on %d carriers\n", distinct);
  }
}

/* ---- 6. a THREAD carries tasks ---- */

typedef struct { m9_mon m; int64_t n; int thread_done; } Carried;
static Carried car;

static void *carried_task (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_task_yield ();
  m9_mon_enter (&car.m);
  car.n++;
  m9_mon_leave (&car.m);
  return NULL;
}

static void *carrier_thread (void *arg, m9_pool *pool)
{
  m9_state err;
  int i;
  (void) arg; (void) pool;
  memset (&err, 0, sizeof err);
  for (i = 0; i < 1000; i++) m9_task_start2 (carried_task, NULL, NULL, "carried", &err);
  return NULL;                  /* returns at once; its tasks still run */
}

static void thread_carries (void)
{
  m9_state err;
  int i;
  memset (&err, 0, sizeof err);
  m9_thread_start2 (carrier_thread, NULL, NULL, &err);
  for (i = 0; i < 5000; i++) {
    m9_mon_enter (&car.m);
    if (car.n == 1000) { m9_mon_leave (&car.m); break; }
    m9_mon_leave (&car.m);
    usleep (1000);
  }
  ok ("a THREAD that returns runs its 1,000 tasks to the end", car.n == 1000);
}

/* ---- 6b. the poller: sleeps and descriptors (stage 3) ---- */

#define SLEEPERS 10000
typedef struct { m9_mon m; int64_t n; } Count;
static Count slept;

static void *sleeper (void *arg, m9_pool *pool)
{
  (void) pool;
  m9_sleep_ms (50 + (intptr_t) arg % 10);
  m9_mon_enter (&slept.m);
  slept.n++;
  m9_mon_signal (&slept.m);
  m9_mon_leave (&slept.m);
  return NULL;
}

static int64_t ticks;
static void *ticker (void *arg, m9_pool *pool)
{
  int i;
  (void) arg; (void) pool;
  for (i = 0; i < 1000; i++) { __atomic_add_fetch (&ticks, 1, __ATOMIC_RELAXED); m9_task_yield (); }
  return NULL;
}

static int pipefd[2];
static int read_why = -9, late_why = -9;
static void *reader (void *arg, m9_pool *pool)
{
  char b;
  (void) arg; (void) pool;
  read_why = m9_task_wait_fd (pipefd[0], 0, -1);
  if (read (pipefd[0], &b, 1) != 1) read_why = -2;
  return NULL;
}

static void *writer (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_sleep_ms (20);
  if (write (pipefd[1], "x", 1) != 1) read_why = -3;
  return NULL;
}

static int nothing[2];
static double late_s;
static void *late (void *arg, m9_pool *pool)
{
  double t0 = now ();
  (void) arg; (void) pool;
  late_why = m9_task_wait_fd (nothing[0], 0, 30);
  late_s = now () - t0;
  return NULL;
}

static void poller (void)
{
  m9_state err;
  intptr_t i;
  double t0, t1;
  int64_t before;
  memset (&err, 0, sizeof err);
  t0 = now ();
  for (i = 0; i < SLEEPERS; i++) m9_task_start2 (sleeper, (void *) i, NULL, "sleeper", &err);
  m9_mon_enter (&slept.m);
  while (slept.n < SLEEPERS) m9_mon_wait (&slept.m);
  m9_mon_leave (&slept.m);
  t1 = now ();
  ok ("10,000 tasks sleep 50-59 ms each, all at once", slept.n == SLEEPERS && t1 - t0 < 2.0);
  printf ("     sleepers: 10,000 slept in %.0f ms\n", (t1 - t0) * 1e3);

  /* The module body sleeps; a ticker on its carrier runs meanwhile. */
  before = ticks;
  m9_task_start2 (ticker, NULL, NULL, "ticker", &err);
  m9_sleep_ms (100);
  ok ("a sleeping task leaves its carrier to the others", __atomic_load_n (&ticks, __ATOMIC_RELAXED) - before == 1000);

  if (pipe (pipefd) != 0 || pipe (nothing) != 0) { ok ("pipes", 0); return; }
  m9_task_start2 (reader, NULL, NULL, "reader", &err);
  m9_task_start2 (writer, NULL, NULL, "writer", &err);
  m9_task_start2 (late, NULL, NULL, "late", &err);
  m9_sleep_ms (200);
  ok ("a task waiting on a pipe wakes when another writes", read_why == 1);
  ok ("a wait with a 30 ms limit ends at the limit", late_why == 0 && late_s >= 0.029 && late_s < 0.5);
}

/* ---- 6c. the monitor hands a stuck carrier's work on (stage 3) ---- */

static int64_t handed, handed_seen = -1;
static Count handdone;

static void *blocker (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  usleep (300000);             /* a blocking call the runtime cannot see */
  handed_seen = __atomic_load_n (&handed, __ATOMIC_ACQUIRE);
  m9_mon_enter (&handdone.m);
  handdone.n++;
  m9_mon_signal (&handdone.m);
  m9_mon_leave (&handdone.m);
  return NULL;
}

static void *queued (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  __atomic_add_fetch (&handed, 1, __ATOMIC_RELEASE);
  m9_mon_enter (&handdone.m);
  handdone.n++;
  m9_mon_signal (&handdone.m);
  m9_mon_leave (&handdone.m);
  return NULL;
}

static void handoff (void)
{
  m9_state err;
  int i;
  memset (&err, 0, sizeof err);
  /* The 1,000 are queued first, the blocker last: a new task runs
     next, so the yield runs the blocker on this carrier, with the
     1,000 queued behind it. */
  for (i = 0; i < 1000; i++) m9_task_start2 (queued, NULL, NULL, "queued", &err);
  m9_task_start2 (blocker, NULL, NULL, "blocker", &err);
  m9_task_yield ();
  m9_mon_enter (&handdone.m);
  while (handdone.n < 1001) m9_mon_wait (&handdone.m);
  m9_mon_leave (&handdone.m);
  printf ("     handoff: %lld of 1,000 ran during the blocking call\n", (long long) handed_seen);
  ok ("tasks queued behind a blocking call run on another carrier meanwhile", handed_seen == 1000);
}

/* ---- 7, 8. the stops, each in a child ---- */

static void *waiter (void *arg, m9_pool *pool)
{
  Cell *c = arg;
  (void) pool;
  m9_mon_enter (&c->m);
  while (!c->v) m9_mon_wait (&c->m);
  m9_mon_leave (&c->m);
  return NULL;
}

static int deep (int n)
{
  volatile char pad[512];
  pad[0] = (char) n;
  return n == 0 ? pad[0] : deep (n + 1) + pad[0];
}

static void *Deep (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  deep (1);
  return NULL;
}

static void child_deadlock (void)
{
  static Cell c;
  m9_state err;
  memset (&err, 0, sizeof err);
  m9_task_start2 (waiter, &c, NULL, "Waiter.Run", &err);
  m9_task_start2 (waiter, &c, NULL, "Waiter.Run", &err);
  m9_mon_enter (&c.m);
  while (!c.v) m9_mon_wait (&c.m);
  m9_mon_leave (&c.m);
}

static void child_overflow (void)
{
  static Cell c;
  m9_state err;
  memset (&err, 0, sizeof err);
  m9_task_start2 (Deep, NULL, NULL, "Deep", &err);
  m9_mon_enter (&c.m);
  while (!c.v) m9_mon_wait (&c.m);
  m9_mon_leave (&c.m);
}

/* stop runs f in a child and answers its stderr; *sig gets the
   signal that ended it, or 0. */
static char *stop (void (*f) (void), int *sig)
{
  static char buf[4096];
  int p[2], st;
  ssize_t n, k = 0;
  pid_t pid;
  fflush (stdout);
  if (pipe (p) != 0) { *sig = 0; return ""; }
  pid = fork ();
  if (pid == 0) {
    alarm (20);                 /* a stop that does not fire is a FAIL, not a hang */
    dup2 (p[1], 2);
    close (p[0]);
    f ();
    _exit (0);
  }
  close (p[1]);
  while ((n = read (p[0], buf + k, sizeof buf - 1 - k)) > 0) k += n;
  buf[k] = 0;
  close (p[0]);
  waitpid (pid, &st, 0);
  *sig = WIFSIGNALED (st) ? WTERMSIG (st) : 0;
  return buf;
}

int main (void)
{
  char *e;
  int sig;
  setvbuf (stdout, NULL, _IOLBF, 0);
  /* The stops run first: a child forked while a THREAD is still
     ending would count it alive, and the deadlock test would wait. */
  e = stop (child_deadlock, &sig);
  ok ("every task waiting stops by name", strstr (e, "every task waits") != NULL && sig != 0);
  ok ("the deadlock stop lists the tasks", strstr (e, "Waiter.Run waits in WAIT") != NULL
      && strstr (e, "the module body waits in WAIT") != NULL);
  printf ("     %s", e);
  e = stop (child_overflow, &sig);
  ok ("a task's stack overflow stops by name", strstr (e, "task stack overflow in Deep") != NULL && sig != 0);
  printf ("     %s", e);
  counts ();
  pingpong ();
  parked ();
  mixed ();
  nested ();
  spreads ();
  poller ();
  handoff ();
  thread_carries ();
  printf ("%s: %d checks, %d failed\n", bad ? "FAIL" : "PASS", checks, bad);
  return bad != 0;
}
