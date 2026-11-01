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
static int order[4], norder = 0;

static void *holder (void *arg, m9_pool *pool)
{
  (void) arg; (void) pool;
  m9_mon_enter (&ca.m);
  order[norder++] = 1;
  m9_mon_enter (&cb.m);
  while (!cb.v) m9_mon_wait (&cb.m);   /* holds A, parks in B */
  m9_mon_leave (&cb.m);
  order[norder++] = 3;
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
  order[norder++] = 2;
  m9_mon_enter (&ca.m);         /* parks until holder leaves A */
  order[norder++] = 4;
  ca.v = 1;
  m9_mon_leave (&ca.m);
  return NULL;
}

static void nested (void)
{
  m9_state err;
  memset (&err, 0, sizeof err);
  m9_task_start2 (holder, NULL, NULL, "holder", &err);
  m9_task_start2 (entrant, NULL, NULL, "entrant", &err);
  while (!ca.v) m9_task_yield ();
  ok ("an entrant parks on a monitor a waiting task holds, then gets it",
      norder == 4 && order[0] == 1 && order[1] == 2 && order[2] == 3 && order[3] == 4);
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
  thread_carries ();
  printf ("%s: %d checks, %d failed\n", bad ? "FAIL" : "PASS", checks, bad);
  return bad != 0;
}
