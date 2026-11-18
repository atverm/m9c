/* numpyexact_driver.c holds NumpyExact to numpy's and pandas' answers.
 *
 * The answers are in numpyexact.golden, recorded by
 * tools/numpyexactgold.py from numpy 2.5.4 and pandas 3.1.1.  Each
 * line names a case and the FNV-1a hash of its answer's bits.  This
 * driver makes the same input from the same splitmix64 stream, runs
 * NumpyExact on it and compares the hash.  Every NaN hashes as
 * 7ff8000000000000.  values (), starts () and ids () must stay the
 * script's, line for line.
 *
 * The driver also counts where the distinctions bite: GroupMean
 * against KahanGroupMean, Sum against a plain loop, and reduceat
 * against Sum of each segment.  A gate that never met them would
 * prove nothing.  A control changes one answer by its last bit and
 * requires the hash to see it. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include "NumpyExact.h"

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

static uint64_t mix_s;
static uint64_t mix_next (void)
{
  uint64_t z;
  mix_s += 0x9E3779B97F4A7C15ULL;
  z = mix_s;
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
  return z ^ (z >> 31);
}

static const double P10[10] = { 1e-3, 1e-2, 1e-1, 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6 };

/* values is the script's values (): one draw an element. */
static void values (int kind, uint64_t seed, int64_t n, double *out)
{
  int64_t nanleft = 0;
  double prev = 0.0;
  mix_s = seed;
  for (int64_t i = 0; i < n; i++) {
    uint64_t x = mix_next ();
    double u = (double) (x >> 11) / 9007199254740992.0;
    double scale = P10[(x & 15) % 10];
    uint64_t sel = (x >> 4) & 63;
    double v;
    switch (kind) {
    case 0: v = (u - 0.5) * scale; break;
    case 1: v = u * scale; break;
    case 2: v = -(u * scale); break;
    case 3:
      if (nanleft > 0) { v = NAN; nanleft--; }
      else if (sel % 16 == 0) { v = NAN; nanleft = (int64_t) ((x >> 10) % 9); }
      else v = (u - 0.5) * scale;
      break;
    case 4:
      if (i > 0 && sel % 4 != 0) v = prev;
      else if (sel == 4) v = -0.0;
      else v = (double) ((x >> 11) % 1000) / 10.0 - 50.0;
      break;
    case 5:
      if (sel == 0) v = INFINITY;
      else if (sel == 1) v = -INFINITY;
      else if (sel < 6) v = -0.0;
      else if (sel < 10) v = 0.0;
      else if (sel == 10) v = u * 1e300;
      else v = (u - 0.5) * scale;
      break;
    case 6: v = (double) ((int64_t) ((x >> 11) % 200001) - 100000) / 100.0; break;
    case 7: v = (sel % 10 == 0) ? NAN : (double) ((x >> 11) % 50001) / 100.0; break;
    default:
      /* Kinds 8 and 9 leave a Kahan residue when a large value leaves
         the window: the clamps of calc_mean act on it. */
      if (sel % 8 == 0) v = u * 1e17;
      else if (sel % 8 < 4) v = 0.0;
      else v = u * 3.0;
      if (kind == 9) v = -v;
      break;
    }
    out[i] = v;
    prev = v;
  }
}

static int cmp_i64 (const void *a, const void *b)
{
  int64_t x = *(const int64_t *) a, y = *(const int64_t *) b;
  return (x > y) - (x < y);
}

/* starts is the script's starts (): mode 1 sorted, distinct, with 0. */
static int64_t starts (int mode, uint64_t seed, int64_t n, int64_t k, int64_t *out)
{
  mix_s = seed;
  for (int64_t i = 0; i < k; i++) out[i] = (int64_t) (mix_next () % (uint64_t) n);
  if (mode != 1) return k;
  out[k] = 0;
  qsort (out, k + 1, sizeof (int64_t), cmp_i64);
  int64_t m = 0;
  for (int64_t i = 0; i <= k; i++)
    if (m == 0 || out[i] != out[m - 1]) out[m++] = out[i];
  return m;
}

/* ids is the script's ids (). */
static void ids (int mode, uint64_t seed, int64_t n, int64_t g, int64_t *out)
{
  mix_s = seed;
  for (int64_t i = 0; i < n; i++) out[i] = (int64_t) (mix_next () % (uint64_t) g);
  if (mode == 1) qsort (out, n, sizeof (int64_t), cmp_i64);
  else if (mode == 2) {
    int64_t lead = (int64_t) (mix_next () % (uint64_t) (n / 4 + 1));
    for (int64_t i = 0; i < lead; i++) out[i] = -1;
    qsort (out + lead, n - lead, sizeof (int64_t), cmp_i64);
  } else if (mode == 3) {
    for (int64_t i = 0; i < n; i++) if (mix_next () % 7 == 0) out[i] = -1;
  }
}

static uint64_t fnv (const double *a, int64_t n)
{
  uint64_t h = 0xCBF29CE484222325ULL;
  for (int64_t i = 0; i < n; i++) {
    double v = isnan (a[i]) ? NAN : a[i];
    uint64_t b;
    memcpy (&b, &v, 8);
    if (isnan (a[i])) b = 0x7FF8000000000000ULL;
    for (int k = 0; k < 8; k++) { h ^= (b >> (8 * k)) & 0xff; h *= 0x100000001B3ULL; }
  }
  return h;
}

static bool same_bits (const double *a, const double *b, int64_t n)
{
  return fnv (a, n) == fnv (b, n);
}

int main (void)
{
  m9_state e = {0};
  FILE *f = fopen ("numpyexact.golden", "r");
  if (!f) { printf ("FAIL: no numpyexact.golden\n"); return 1; }
  char line[256], op[16], what[300];
  int bad[8] = {0}, cases[8] = {0};
  const char *ops[7] = { "sum", "mean", "reduceat", "kahan", "group", "roll", NULL };
  int tookReduceat = 0, reduceatNotKahan = 0, sumNotPlain = 0, segNotSum = 0;
  int64_t cap = 8192;
  double *a = malloc (cap * sizeof (double)), *o = malloc (cap * sizeof (double)),
         *o2 = malloc (cap * sizeof (double));
  int64_t *iv = malloc ((cap + 1) * sizeof (int64_t));
  bool controlDone = false;
  NumpyExact_m9init (&e);
  while (fgets (line, sizeof line, f)) {
    int kind, ci;
    unsigned long long seed, p3, want;
    long long n, p1, p2;
    if (line[0] == '#') continue;
    if (sscanf (line, "%15s %d %llu %lld %lld %lld %llu %llx", op, &kind, &seed, &n, &p1, &p2, &p3, &want) != 8) {
      printf ("FAIL: cannot read golden line: %s", line);
      return 1;
    }
    for (ci = 0; ops[ci] && strcmp (ops[ci], op) != 0; ci++) ;
    if (!ops[ci]) { printf ("FAIL: unknown op %s\n", op); return 1; }
    values (kind, seed, n, a);
    m9_sl_F64 av = { a, n };
    uint64_t got = 0;
    e.exc = NULL;
    switch (ci) {
    case 0: {
      double s = NumpyExact_Sum (av, &e), plain = 0.0;
      for (int64_t i = 0; i < n; i++) plain += a[i];
      if (!same_bits (&s, &plain, 1)) sumNotPlain++;
      got = fnv (&s, 1);
      if (!controlDone && n >= 8 && isfinite (s) && s != 0.0) {
        double t = nextafter (s, INFINITY);
        ck (fnv (&t, 1) != want, "control: an answer one bit off is seen");
        controlDone = true;
      }
      break; }
    case 1: { double s = NumpyExact_Mean (av, &e); got = fnv (&s, 1); break; }
    case 2: {
      int64_t k = starts ((int) p2, p3, n, p1, iv);
      m9_sl_I64 sv = { iv, k };
      m9_sl_F64 ov = { o, k };
      NumpyExact_ReduceAt (av, sv, &ov, &e);
      for (int64_t i = 0; i < k; i++) {
        int64_t s0 = iv[i], e0 = (i + 1 < k) ? iv[i + 1] : n;
        if (s0 < e0) {
          m9_state e2 = {0};
          double whole = NumpyExact_Sum ((m9_sl_F64){ a + s0, e0 - s0 }, &e2);
          if (!same_bits (&whole, &o[i], 1)) segNotSum++;
        }
      }
      got = fnv (o, k);
      break; }
    case 3: case 4: {
      ids ((int) p2, p3, n, p1, iv);
      m9_sl_I64 idv = { iv, n };
      m9_sl_F64 ov = { o, p1 }, ov2 = { o2, p1 };
      if (ci == 3) NumpyExact_KahanGroupMean (av, idv, &ov, &e);
      else {
        bool mono = true;
        for (int64_t i = 0; i < n; i++) {
          if (isnan (a[i])) mono = false;
          if (i > 0 && iv[i] < iv[i - 1]) mono = false;
        }
        NumpyExact_GroupMean (av, idv, &ov, &e);
        m9_state e2 = {0};
        NumpyExact_KahanGroupMean (av, idv, &ov2, &e2);
        if (mono) {
          tookReduceat++;
          if (!same_bits (o, o2, p1)) reduceatNotKahan++;
        }
      }
      got = fnv (o, p1);
      break; }
    default: {
      m9_sl_F64 ov = { o, n };
      NumpyExact_RollMean (av, p1, p2, p3 != 0, &ov, &e);
      got = fnv (o, n);
      break; }
    }
    cases[ci]++;
    if (e.exc != NULL || got != want) {
      bad[ci]++;
      if (bad[ci] <= 3) {
        snprintf (what, sizeof what, "%s %s", e.exc ? "raised on" : "differs on", line);
        what[strcspn (what, "\n")] = 0;
        ck (false, what);
      }
    } else checks++;
  }
  fclose (f);
  for (int i = 0; ops[i]; i++)
    printf ("numpyexact: %-8s %4d cases, %d differ\n", ops[i], cases[i], bad[i]);
  printf ("numpyexact: GroupMean took reduceat in %d cases; in %d of them KahanGroupMean differs\n",
          tookReduceat, reduceatNotKahan);
  printf ("numpyexact: Sum differs from a plain loop in %d cases; %d reduceat segments differ from Sum of the segment\n",
          sumNotPlain, segNotSum);
  ck (controlDone, "the control ran");
  ck (reduceatNotKahan > 0, "some reduceat group differs from KahanGroupMean");
  ck (sumNotPlain > 0, "some Sum differs from a plain loop");
  ck (segNotSum > 0, "some reduceat segment differs from Sum of it");
  for (int i = 0; ops[i]; i++) if (bad[i] > 0) fails++;

  /* The errors the headings promise. */
  {
    double x[3] = { 1.0, 2.0, 3.0 }, r[3];
    int64_t s[2] = { 0, 3 }, idb[3] = { 0, 2, 0 };
    m9_sl_F64 xv = { x, 3 }, rv = { r, 3 }, r2 = { r, 2 };
    e.exc = NULL;
    NumpyExact_ReduceAt (xv, (m9_sl_I64){ s, 2 }, &rv, &e);
    ck (e.exc == &m9_exc_IndexError, "ReduceAt: a start at LEN (a) raises IndexError");
    e.exc = NULL;
    NumpyExact_GroupMean (xv, (m9_sl_I64){ idb, 3 }, &r2, &e);
    ck (e.exc == &m9_exc_IndexError, "GroupMean: an id past the groups raises IndexError");
    e.exc = NULL;
    NumpyExact_RollMean (xv, 2, 3, false, &rv, &e);
    ck (e.exc == &m9_exc_ValueRange, "RollMean: minPeriods above the window raises ValueRange");
    e.exc = NULL;
    NumpyExact_RollMean (xv, 2, 1, false, &r2, &e);
    ck (e.exc == &m9_exc_IndexError, "RollMean: a short out raises IndexError");
  }
  printf ("numpyexact: %d checks, %d failed\n", checks, fails);
  return fails > 0;
}
