/* sort_driver.c -- the runtime's radix sorts (m9rt.h: m9_sort_f64,
   m9_sort_i64, m9_argsort_f64, m9_argsort_i64) held to a stable
   reference -- qsort over the value with the index as the tie-break,
   which is what a stable sort answers -- over 400 arrays of seven
   shapes: random reals, ten repeated values, sorted, reversed, the two
   zeros among 1.5s, any finite bit pattern, decimals of three places;
   lengths 0..99 and up to 5,000, so both the insertion sort below 64
   and every radix pass with and without a skipped byte are reached.
   -0.0 and 0.0 are one key and keep their input order among
   themselves, as the merge sort left them.  Under M9_SORT_PORTABLE the
   runtime answers 0 (the caller sorts) and this says so.  Shown able
   to fail: the index not carried through a pass fails the argsorts
   (2026-10-25).  Speed is printed, never gated. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "m9rt.h"

static long bad = 0, checks = 0;
static uint64_t rs = 0x9E3779B97F4A7C15ull;
static uint64_t rnd (void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static double now (void) { struct timespec t; clock_gettime (CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static const double *keys_d;
static const int64_t *keys_i;
static int cmp_arg_d (const void *a, const void *b)
{
  int64_t i = *(const int64_t *) a, j = *(const int64_t *) b;
  if (keys_d[i] < keys_d[j]) return -1;
  if (keys_d[i] > keys_d[j]) return 1;
  return (i > j) - (i < j);
}
static int cmp_arg_i (const void *a, const void *b)
{
  int64_t i = *(const int64_t *) a, j = *(const int64_t *) b;
  if (keys_i[i] < keys_i[j]) return -1;
  if (keys_i[i] > keys_i[j]) return 1;
  return (i > j) - (i < j);
}

static double value (int shape, int64_t i, int64_t n)
{
  switch (shape) {
  case 0: return ((rnd () >> 11) * (1.0 / 9007199254740992.0) - 0.5) * 1e6;
  case 1: return (double) (int64_t) (rnd () % 10) - 5;
  case 2: return (double) i;
  case 3: return (double) (n - i);
  case 4: return (rnd () % 3 == 0) ? -0.0 : (rnd () % 3 == 1 ? 0.0 : 1.5);
  case 5: { uint64_t b = rnd (); double v; memcpy (&v, &b, 8); if (v != v || v > 1e308 || v < -1e308) v = 2.0; return v; }
  default: return (double) (int64_t) (rnd () % 100000) * 1e-3;
  }
}

int main (void)
{
  int portable = getenv ("M9_SORT_PORTABLE") != NULL;
  for (int round = 0; round < 400; round++) {
    int64_t n = round < 100 ? round : (int64_t) (rnd () % 5000) + 1;
    int shape = round % 7;
    double *v = malloc ((size_t) (n + 1) * 8), *d = malloc ((size_t) (n + 1) * 8);
    int64_t *w = malloc ((size_t) (n + 1) * 8), *ix = malloc ((size_t) (n + 1) * 8), *iq = malloc ((size_t) (n + 1) * 8);
    for (int64_t i = 0; i < n; i++) { v[i] = value (shape, i, n); w[i] = (int64_t) (v[i] * 7); }
    /* the stable order of v, by reference */
    for (int64_t i = 0; i < n; i++) iq[i] = i;
    keys_d = v; qsort (iq, (size_t) n, 8, cmp_arg_d);
    /* m9_sort_f64: the values in that order, -0.0 and 0.0 as they came */
    memcpy (d, v, (size_t) n * 8);
    int did = m9_sort_f64 (d, n);
    checks++;
    if (portable) { if (did) { bad++; printf ("FAIL sort_f64 sorted under M9_SORT_PORTABLE\n"); } }
    else if (!did) { bad++; printf ("FAIL sort_f64 declined\n"); }
    else for (int64_t i = 0; i < n; i++) if (memcmp (&d[i], &v[iq[i]], 8) != 0) { bad++; printf ("FAIL sort_f64 shape %d n %lld at %lld\n", shape, (long long) n, (long long) i); break; }
    /* argsort f64 */
    checks++;
    did = m9_argsort_f64 (v, ix, n);
    if (portable) { if (did) { bad++; printf ("FAIL argsort_f64 sorted under M9_SORT_PORTABLE\n"); } }
    else if (!did || memcmp (ix, iq, (size_t) n * 8) != 0) { bad++; printf ("FAIL argsort_f64 shape %d n %lld\n", shape, (long long) n); }
    /* i64 and its argsort */
    for (int64_t i = 0; i < n; i++) iq[i] = i;
    keys_i = w; qsort (iq, (size_t) n, 8, cmp_arg_i);
    checks++;
    did = m9_argsort_i64 (w, ix, n);
    if (portable) { if (did) { bad++; printf ("FAIL argsort_i64 under M9_SORT_PORTABLE\n"); } }
    else if (!did || memcmp (ix, iq, (size_t) n * 8) != 0) { bad++; printf ("FAIL argsort_i64 shape %d n %lld\n", shape, (long long) n); }
    int64_t *ws = malloc ((size_t) (n + 1) * 8);
    for (int64_t i = 0; i < n; i++) ws[i] = w[iq[i]];
    checks++;
    did = m9_sort_i64 (w, n);
    if (portable) { if (did) { bad++; printf ("FAIL sort_i64 under M9_SORT_PORTABLE\n"); } }
    else if (!did || memcmp (w, ws, (size_t) n * 8) != 0) { bad++; printf ("FAIL sort_i64 shape %d n %lld\n", shape, (long long) n); }
    free (v); free (d); free (w); free (ix); free (iq); free (ws);
  }
  if (!portable) {
    int64_t N = 1000000;
    double *src = malloc ((size_t) N * 8), *d = malloc ((size_t) N * 8);
    int64_t *w = malloc ((size_t) N * 8), *ix = malloc ((size_t) N * 8);
    double best, t0, t1;
    for (int64_t i = 0; i < N; i++) src[i] = ((rnd () >> 11) * (1.0 / 9007199254740992.0) - 0.5) * 1e6;
    best = 1e9; for (int r = 0; r < 3; r++) { memcpy (d, src, (size_t) N * 8); t0 = now (); m9_sort_f64 (d, N); t1 = now (); if (t1 - t0 < best) best = t1 - t0; }
    printf ("a million doubles: %.1f ms", best * 1e3);
    best = 1e9; for (int r = 0; r < 3; r++) { for (int64_t i = 0; i < N; i++) w[i] = (int64_t) src[i]; t0 = now (); m9_sort_i64 (w, N); t1 = now (); if (t1 - t0 < best) best = t1 - t0; }
    printf (", int64s: %.1f ms", best * 1e3);
    best = 1e9; for (int r = 0; r < 3; r++) { t0 = now (); m9_argsort_f64 (src, ix, N); t1 = now (); if (t1 - t0 < best) best = t1 - t0; }
    printf (", the argsort: %.1f ms\n", best * 1e3);
    free (src); free (d); free (w); free (ix);
  }
  if (bad) { printf ("sort_driver: %ld of %ld checks FAIL\n", bad, checks); return 1; }
  printf ("sort_driver: %ld checks ok%s\n", checks, portable ? " (M9_SORT_PORTABLE: the runtime declined every one)" : "");
  return 0;
}
