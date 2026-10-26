/* blockreuse_driver.c -- the per-thread cache of large pool blocks
   (m9rt.h) held to its own policy, counted, not timed:
     a 16 MB carve freed and made again 50 times takes a kept block 49
     times when the cache is on, 0 times under M9_BLOCK_REUSE=0 (the
     battery runs both; the second is the control that shows the count
     can read 0);
     a block is not spent on a carve under a quarter of its size, and
     a block above the 128 MB cap is not kept;
     ten M9 threads, one at a time, that each carve 100 MB and return
     leave nothing kept: the process's peak RSS grows by under three
     such blocks, where blocks leaked at thread exit would be ten;
     and 1,000 threads, one at a time, that each hold four
     minimum-size blocks and free them grow it by under 16 MB, where
     the small cache kept per thread and never given back (the second
     review's R1, 2026-10-26) grew it 63 MB on the M4 (a block counts
     by the pages touched).
   Speed is in the progress report of 2026-10-25, not here. */
#define _DEFAULT_SOURCE       /* ru_maxrss: glibc */
#define _DARWIN_C_SOURCE      /* ru_maxrss: macOS hides it under strict POSIX */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include "m9rt.h"

static int bad = 0, checks = 0;
static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { bad++; printf ("FAIL %s\n", what); }
}

static void cycle (m9_pool *pool, int64_t bytes, int times)
{
  m9_state err;
  for (int i = 0; i < times; i++) {
    memset (&err, 0, sizeof err);
    unsigned char *p = m9_pool_alloc (pool, 1, bytes, &err);
    if (p == NULL || err.exc != NULL) { printf ("FAIL alloc\n"); bad++; return; }
    p[bytes - 1] = 1;
    m9_pool_free (pool);
  }
}

static int64_t done = 0;

static void *worker (void *arg)
{
  m9_pool pool;
  (void) arg;
  memset (&pool, 0, sizeof pool);
  cycle (&pool, 100 << 20, 1);
  __atomic_add_fetch (&done, 1, __ATOMIC_RELEASE);
  return NULL;
}

static long maxrss_bytes (void)
{
  struct rusage ru;
  getrusage (RUSAGE_SELF, &ru);
#ifdef __APPLE__
  return ru.ru_maxrss;
#else
  return ru.ru_maxrss * 1024L;
#endif
}

static int64_t sdone = 0;

/* four frame-sized pools at once, freed: the small cache keeps four */
static void *small_worker (void *arg)
{
  m9_state err;
  m9_pool p[4];
  (void) arg;
  memset (&err, 0, sizeof err);
  memset (p, 0, sizeof p);
  for (int i = 0; i < 4; i++) memset (m9_pool_alloc (&p[i], 1, 1000, &err), 1, 1000);
  for (int i = 0; i < 4; i++) m9_pool_free (&p[i]);
  __atomic_add_fetch (&sdone, 1, __ATOMIC_RELEASE);
  return NULL;
}

int main (void)
{
  const char *e = getenv ("M9_BLOCK_REUSE");
  int on = !(e != NULL && e[0] == '0');
  m9_pool pool;
  m9_state err;
  char what[200];
  memset (&pool, 0, sizeof pool);

  cycle (&pool, 16 << 20, 50);
  snprintf (what, sizeof what, "16 MB carved and freed 50 times: %lld taken from a kept block (%s)",
            (long long) m9_block_reuse_hits (), on ? "cache on: 49 expected" : "M9_BLOCK_REUSE=0: 0 expected");
  ok (what, m9_block_reuse_hits () == (on ? 49 : 0));
  printf ("%s\n", what);
  if (on) {
    int64_t h0 = m9_block_reuse_hits ();
    /* the 16 MB block is kept now; a 2 MB carve must not take it */
    cycle (&pool, 2 << 20, 1);
    ok ("a 2 MB carve does not take the kept 16 MB block", m9_block_reuse_hits () == h0);
    /* and a 16 MB carve still does */
    cycle (&pool, 16 << 20, 1);
    ok ("a 16 MB carve takes it again", m9_block_reuse_hits () == h0 + 1);
    /* a block above the cap is not kept */
    int64_t held = m9_block_reuse_held ();
    cycle (&pool, 200 << 20, 1);
    ok ("a 200 MB block is not kept (above the 128 MB cap)", m9_block_reuse_held () == held);
    ok ("something is held after the cycles", held > 0);
  } else {
    ok ("nothing is held with the cache off", m9_block_reuse_held () == 0);
  }

  /* threads, ONE AT A TIME: what each kept goes with it, so the peak
     RSS grows by about one block, not ten */
  long before = maxrss_bytes ();
  for (int t = 0; t < 10; t++) {
    int64_t want = t + 1;
    int waited = 0;
    memset (&err, 0, sizeof err);
    if (m9_thread_start (worker, NULL, &err) != 0) { printf ("FAIL thread start\n"); bad++; break; }
    while (__atomic_load_n (&done, __ATOMIC_ACQUIRE) < want && waited < 2000) { m9_sleep_ms (5); waited += 5; }
    m9_sleep_ms (20);                        /* the thread's return after its last store */
  }
  long after = maxrss_bytes ();
  snprintf (what, sizeof what, "ten threads, one at a time, each carving 100 MB and returning: peak RSS grew %ld MB (under 300 wanted; leaked blocks would be 1,000)",
            (after - before) >> 20);
  ok (what, after - before < 300L << 20);
  printf ("%s\n", what);

  before = maxrss_bytes ();
  for (int t = 0; t < 1000; t++) {
    int64_t want = t + 1;
    int waited = 0;
    memset (&err, 0, sizeof err);
    if (m9_thread_start (small_worker, NULL, &err) != 0) { printf ("FAIL thread start\n"); bad++; break; }
    while (__atomic_load_n (&sdone, __ATOMIC_ACQUIRE) < want && waited < 2000) { m9_sleep_ms (1); waited++; }
  }
  m9_sleep_ms (50);
  after = maxrss_bytes ();
  snprintf (what, sizeof what, "1,000 threads, one at a time, each freeing four 64 KB blocks: peak RSS grew %ld MB (under 16 wanted; the leaking runtime grew 63)",
            (after - before) >> 20);
  ok (what, after - before < 16L << 20);
  printf ("%s\n", what);

  if (bad) { printf ("blockreuse_driver: %d of %d checks FAIL\n", bad, checks); return 1; }
  printf ("blockreuse_driver: %d checks ok\n", checks);
  return 0;
}
