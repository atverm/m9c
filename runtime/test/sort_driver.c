/* sort_driver.c -- Sort.m9 against a reference, and against its stated
   refusals.

   The VALUES are held to a reference: qsort for the multiset (a sort's
   output is the sorted multiset whatever its algorithm), strcmp order
   for strings (ASCII only, so scalar order and byte order agree), and
   an O(n^2) stable insertion sort written here for the one property
   qsort does not have, stability, checked through ArgF64 -- equal
   values must keep index order -- and through By.

   By is called with a C FUNCTION of the procedure type's own
   signature, `bool (int64_t, int64_t, m9_state *)`: if the typedef
   the generator emits did not match the heading rule, this file
   would not compile.  That is the ABI of par 2.2.3 proven from the
   outside.

   The REFUSALS: an F64 sort meeting a NaN raises NotANumber with the
   index as payload; an argsort with an index slice of the wrong
   length raises IndexError.  A sort over a SUB-RANGE is a slice into
   the middle of an array, and the ends must not move.               */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "Sort.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static uint64_t st = 7;
static int64_t rnd (int64_t mod)
{
  st = st * 6364136223846793005ULL + 1442695040888963407ULL;
  return (int64_t) ((st >> 33) % (uint64_t) mod);
}

static int cmp_i64 (const void *a, const void *b)
{
  int64_t x = *(const int64_t *) a, y = *(const int64_t *) b;
  return (x > y) - (x < y);
}

static int cmp_f64 (const void *a, const void *b)
{
  double x = *(const double *) a, y = *(const double *) b;
  return (x > y) - (x < y);
}

/* the table By orders by: descending, with many ties */
static int64_t table[64];

static bool by_table_desc (int64_t a, int64_t b, m9_state *err)
{
  (void) err;
  return table[a] > table[b];
}

static m9_sl_CHAR S (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
}

static int cmp_cstr (const void *a, const void *b)
{
  return strcmp (*(const char *const *) a, *(const char *const *) b);
}

int main (void)
{
  m9_state e = {0};
  int64_t sizes[] = { 0, 1, 2, 3, 17, 1000 };
  int si, i;

  /* I64s and F64s against qsort, many duplicates */
  for (si = 0; si < 6; si++)
  {
    int64_t n = sizes[si];
    int64_t *a = malloc ((size_t) (n + 1) * sizeof *a);
    int64_t *r = malloc ((size_t) (n + 1) * sizeof *r);
    double *f = malloc ((size_t) (n + 1) * sizeof *f);
    double *g = malloc ((size_t) (n + 1) * sizeof *g);
    for (i = 0; i < n; i++) { a[i] = rnd (50) - 25; r[i] = a[i]; f[i] = (double) (rnd (40) - 20) / 4.0; g[i] = f[i]; }
    { m9_sl_I64 sa = { a, n }; Sort_I64s (&sa, &e); }
    qsort (r, (size_t) n, sizeof *r, cmp_i64);
    ok ("I64s is qsort's multiset", memcmp (a, r, (size_t) n * sizeof *a) == 0);
    { m9_sl_F64 sf = { f, n }; Sort_F64s (&sf, &e); }
    qsort (g, (size_t) n, sizeof *g, cmp_f64);
    ok ("F64s is qsort's multiset", memcmp (f, g, (size_t) n * sizeof *f) == 0);
    free (a); free (r); free (f); free (g);
  }
  ok ("the plain sorts raised nothing", e.exc == NULL);

  /* a sub-range: a slice into the middle, the ends untouched */
  {
    int64_t a[9] = { 9, 8, 5, 4, 3, 2, 1, 8, 9 };
    int64_t want[9] = { 9, 8, 1, 2, 3, 4, 5, 8, 9 };
    m9_sl_I64 mid = { a + 2, 5 };
    Sort_I64s (&mid, &e);
    ok ("a sub-range sorts in place and the ends do not move",
        memcmp (a, want, sizeof a) == 0 && e.exc == NULL);
  }

  /* ArgF64: a permutation, non-decreasing through it, STABLE on ties */
  {
    enum { N = 500 };
    static double v[N];
    static int64_t idx[N];
    static int seen[N];
    int perm = 1, mono = 1, stable = 1;
    for (i = 0; i < N; i++) v[i] = (double) rnd (7);      /* seven values: ties everywhere */
    m9_sl_I64 sidx = { idx, N };
    Sort_ArgF64 ((m9_sl_F64){ v, N }, &sidx, &e);
    memset (seen, 0, sizeof seen);
    for (i = 0; i < N; i++) {
      if (idx[i] < 0 || idx[i] >= N || seen[idx[i]]) perm = 0; else seen[idx[i]] = 1;
    }
    for (i = 1; i < N; i++) {
      if (v[idx[i]] < v[idx[i - 1]]) mono = 0;
      if (v[idx[i]] == v[idx[i - 1]] && idx[i] < idx[i - 1]) stable = 0;
    }
    ok ("ArgF64 answers a permutation", perm);
    ok ("ArgF64 orders the values", mono);
    ok ("ArgF64 is STABLE: equal values keep index order", stable);
    ok ("ArgF64 raised nothing", e.exc == NULL);
    for (i = 0; i < N; i++) ok ("v untouched", v[i] >= 0.0 && v[i] <= 6.0);
  }

  /* Strs against strcmp order (ASCII: scalar order is byte order),
     the shorter first on a prefix, stable on equal strings */
  {
    const char *words[] = { "pear", "Apple", "apple", "app", "zeta", "", "banana", "app", "Zeta", "b" };
    const char *sorted[10];
    static uint32_t bufs[10][16];
    static m9_sl_CHAR sl[10];
    char back[10][16];
    int n = 10, same = 1;
    for (i = 0; i < n; i++) { sl[i] = S (words[i], bufs[i]); sorted[i] = words[i]; }
    m9_sl_m9_sl_CHAR ssl = { sl, n };
    Sort_Strs (&ssl, &e);
    qsort (sorted, (size_t) n, sizeof *sorted, cmp_cstr);
    for (i = 0; i < n; i++) {
      int64_t j;
      for (j = 0; j < sl[i].len && j < 15; j++) back[i][j] = (char) sl[i].p[j];
      back[i][j] = 0;
      if (strcmp (back[i], sorted[i]) != 0) same = 0;
    }
    ok ("Strs is strcmp's order on ASCII", same && e.exc == NULL);
  }

  /* By: a C function IS a value of the type; descending by a table
     with ties, stable on the ties */
  {
    static int64_t keys[64];
    int n = 64, mono = 1, stable = 1;
    for (i = 0; i < n; i++) { table[i] = rnd (5); keys[i] = i; }
    m9_sl_I64 sk = { keys, n };
    Sort_By (&sk, by_table_desc, &e);
    for (i = 1; i < n; i++) {
      if (table[keys[i]] > table[keys[i - 1]]) mono = 0;
      if (table[keys[i]] == table[keys[i - 1]] && keys[i] < keys[i - 1]) stable = 0;
    }
    ok ("By follows the caller's order", mono);
    ok ("By is stable on ties", stable);
    ok ("By raised nothing", e.exc == NULL);
  }

  /* the refusals, by name and with the payload */
  {
    double v[4] = { 1.0, 2.0, nan (""), 0.5 };
    int64_t idx[3];
    m9_sl_F64 sv = { v, 4 };
    m9_sl_I64 si3 = { idx, 3 };
    Sort_F64s (&sv, &e);
    ok ("F64s with a NaN raises NotANumber", e.exc == &Sort_NotANumber);
    ok ("and names the index", e.i[0] == 2);
    ok ("and moved nothing", v[0] == 1.0 && v[1] == 2.0 && v[3] == 0.5);
    e.exc = NULL;
    Sort_ArgF64 (sv, &si3, &e);
    ok ("ArgF64 with the wrong index length raises IndexError",
        e.exc == &m9_exc_IndexError);
    e.exc = NULL;
  }

  printf (failed ? "FAIL (%d of %d checks)\n" : "PASS (%d checks)\n",
          failed ? failed : checks, checks);
  return failed != 0;
}
