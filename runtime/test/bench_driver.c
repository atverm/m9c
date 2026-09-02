/* bench_driver.c -- the bench store (4000x4000 f8, 64 chunks) read
   by compiled M9, closing the P4 measurement item.
   - n must be EXACT (order-free);
   - the recorded nansum 6324247734.661942 is numpy's pairwise sum;
     the chunk-sequential sum differs in the tail and is asserted
     within 1.0 absolute (12 agreeing digits) and printed in full;
   - timed twice in-process (cold includes the HTTP fetches, warm
     hits the single-chunk cache pattern again), nproc recorded --
     the house rule: measure twice, page caches lie;
   - the store handle is closed BEFORE the array: handle-copy
     refcounts make the order irrelevant, and this proves it.        */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include "ZarrStore.h"

static m9_sl_CHAR sl (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
}

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

static int64_t ix[2];
static m9_sl_I64 at (int64_t r, int64_t c)
{
  ix[0] = r; ix[1] = c;
  return (m9_sl_I64){ ix, 2 };
}

static double now_s (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return (double) ts.tv_sec + 1e-9 * (double) ts.tv_nsec;
}

/* chunk-band scan: friendly to the single-chunk cache */
static void scan (ZarrStore_Array *a, m9_state *err,
                  double *sum, int64_t *n)
{
  int64_t cr, cc, r, c, gr, gc;
  double v;
  *sum = 0; *n = 0;
  for (cr = 0; cr < 8; cr++)
    for (cc = 0; cc < 8; cc++)
      for (r = 0; r < 500; r++)
        for (c = 0; c < 500; c++) {
          gr = cr * 500 + r; gc = cc * 500 + c;
          v = ZarrStore_GetF64 (&a, at (gr, gc), err);
          if (!isnan (v)) { *sum += v; (*n)++; }
        }
}

int main (void)
{
  m9_state err = {0};
  uint32_t ub[64];
  double sum, t0, t1, t2;
  int64_t n;

  ZarrStore_Store *s =
    ZarrStore_Open (sl ("http://127.0.0.1:18930", ub), &err);
  ZarrStore_Array *a =
    ZarrStore_OpenArray (s, sl ("bench.zarr", ub), &err);
  ck (err.exc == NULL && a != NULL, "OpenArray bench.zarr");

  /* refcounts under test: the store handle goes first */
  ZarrStore_Close (&s, &err);
  ck (err.exc == NULL, "Close before CloseArray (rc keeps the store)");

  t0 = now_s ();
  scan (a, &err, &sum, &n);
  t1 = now_s ();
  if (err.exc) {
    int64_t i;
    printf ("scan exc: %s  i0=%lld d0=%g  msg: ", err.exc->name,
            (long long) err.i[0], err.d[0]);
    for (i = 0; i < err.s[0].len && i < 60; i++)
      putchar ((int) (((const uint32_t *) err.s[0].p)[i] & 0xff));
    printf ("\n");
  }
  ck (err.exc == NULL, "cold scan raises nothing");
  ck (n == 15800721, "n = 15800721");
  ck (fabs (sum - 6324247734.661942) < 1.0,
      "nansum within 1.0 of the pairwise golden");
  printf ("nansum = %.17g  (recorded pairwise golden 6324247734.661942)\n",
          sum);

  scan (a, &err, &sum, &n);
  t2 = now_s ();
  ck (n == 15800721, "warm scan agrees");

  printf ("cold %.2fs  warm %.2fs  nproc %ld  (16M checked GetF64 each)\n",
          t1 - t0, t2 - t1, sysconf (_SC_NPROCESSORS_ONLN));

  ZarrStore_CloseArray (&a, &err);
  ck (err.exc == NULL, "CloseArray after Close");

  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
