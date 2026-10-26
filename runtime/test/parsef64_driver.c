/* parsef64_driver.c -- m9_strtod (Eisel-Lemire where it decides, libc's
   strtod where it does not; m9rt.h) held to strtod bit for bit:
     a million random doubles printed by %.17g (every bit back), %.15g,
     %.6f, %.3e and %g;
     a million random significands of 1 to 19 digits with a point placed
     anywhere and an exponent in -330..310, the shape that reaches the
     128-bit product and its halfway rule;
     the halfway strings themselves: random doubles' exact midpoints to
     their neighbours, printed with every digit (these have more than
     19 digits and go to strtod; they hold the fallback);
     the known hard cases -- 2^53 + 1, the smallest normal, 1e23, the
     largest finite, the subnormal edge, "0.1" and its kin -- and the
     shapes strtod stops at: a lone sign, a lone point, "1e", "inf",
     "nan", "0x10", text;
     and under M9_PARSE_PORTABLE every answer is strtod's with no fast
     answer counted (the battery runs both; the second is the control).
   Shown able to fail: one bit flipped in a table entry's high word
   fails 1,813 of the two million (2026-10-25); the low word cleared
   fails none -- it decides only where the first product is ambiguous,
   which these strings reach rarely.
   Speed is printed, never gated. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "m9rt.h"

static long bad = 0, checks = 0;
static uint64_t rs = 0x9E3779B97F4A7C15ull;
static uint64_t rnd (void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }

static double now (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

/* the same bits, NaN against NaN counted equal */
static void same (const char *s, const char *what)
{
  double a = m9_strtod (s), b = strtod (s, NULL);
  uint64_t ua, ub;
  memcpy (&ua, &a, 8);
  memcpy (&ub, &b, 8);
  checks++;
  if (ua != ub && !(isnan (a) && isnan (b))) {
    bad++;
    if (bad <= 8) printf ("FAIL %s: \"%s\" -> %.17g (%016llx), strtod %.17g (%016llx)\n", what, s, a, (unsigned long long) ua, b, (unsigned long long) ub);
  }
}

int main (void)
{
  const char *e = getenv ("M9_PARSE_PORTABLE");
  int portable = e != NULL;
  char buf[1200];
  int64_t h0 = m9_parse_f64_hits ();

  /* random doubles in five layouts */
  for (int i = 0; i < 200000; i++) {
    uint64_t b = rnd ();
    double d;
    memcpy (&d, &b, 8);
    if (!isfinite (d)) continue;
    snprintf (buf, sizeof buf, "%.17g", d); same (buf, "%.17g");
    snprintf (buf, sizeof buf, "%.15g", d); same (buf, "%.15g");
    snprintf (buf, sizeof buf, "%g", d); same (buf, "%g");
    double m = (double) (int64_t) (rnd () % 2000000000ull) / 1000.0 - 1000000.0;
    snprintf (buf, sizeof buf, "%.6f", m); same (buf, "%.6f");
    snprintf (buf, sizeof buf, "%.3e", m); same (buf, "%.3e");
  }
  /* 1 to 19 digits, a point anywhere, an exponent in -330..310 */
  for (int i = 0; i < 1000000; i++) {
    int nd = 1 + (int) (rnd () % 19), pt = (int) (rnd () % (nd + 1)), ex = (int) (rnd () % 641) - 330, k = 0;
    if (rnd () % 4 == 0) buf[k++] = '-';
    for (int j = 0; j < nd; j++) {
      if (j == pt && j > 0) buf[k++] = '.';
      buf[k++] = (char) ('0' + (j == 0 && nd > 1 ? 1 + rnd () % 9 : rnd () % 10));
    }
    if (rnd () % 2 == 0) k += snprintf (buf + k, sizeof buf - k, "e%d", ex);
    buf[k] = 0;
    same (buf, "19-digit");
  }
  /* exact midpoints between neighbouring doubles, every digit printed */
  for (int i = 0; i < 20000; i++) {
    uint64_t b = rnd () >> 2;
    double d, n2;
    memcpy (&d, &b, 8);
    if (!isfinite (d) || d == 0) continue;
    n2 = nextafter (d, INFINITY);
    if (!isfinite (n2)) continue;
    /* the midpoint as the exact sum printed at half: %.1000g of (d + n2) is
       exact for a double, and the midpoint is that divided by two, which
       the string cannot carry -- so print d and n2 each exactly and form
       the midpoint's digits by averaging is not a string operation; use
       long double, exact for the sum of two doubles of equal exponent */
    long double mid = ((long double) d + (long double) n2) / 2.0L;
    snprintf (buf, sizeof buf, "%.1100Lg", mid);
    same (buf, "midpoint");
  }
  /* the known hard ones and the shapes strtod stops at */
  {
    static const char *hard[] = {
      "9007199254740993", "9007199254740992.5", "2.2250738585072011e-308", "2.2250738585072014e-308",
      "1e23", "1e22", "8.5e22", "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308",
      "4.9406564584124654e-324", "2.4703282292062327e-324", "2.4703282292062328e-324", "1e-400", "1e400",
      "0.1", "0.2", "0.3", "1.1", "123456789012345678", "1234567890123456789", "12345678901234567890",
      "0.000000000000000000000000000000000000001", "7.2057594037927933e16", "9223372036854775807",
      "18446744073709551615", "18446744073709551616", "3.14159265358979323846264338327950288",
      "1e", "1e+", "1e-", ".", "-", "+", "", "e5", ".5", "5.", "-0", "-0.0", "0e999", "00000.000001",
      "inf", "-inf", "infinity", "nan", "nan(123)", "0x10", "0x1p3", "abc", " 1", "1 ", "1,5", "1.5e3x",
      "00000000000000000000000000000001", "100000000000000000000000000000000", "1.00000000000000000000000001" };
    for (unsigned i = 0; i < sizeof hard / sizeof hard[0]; i++) same (hard[i], "hard");
  }
  {
    int64_t hits = m9_parse_f64_hits () - h0;
    char what[160];
    snprintf (what, sizeof what, "%lld of %ld answers were the fast path's (%s)", (long long) hits, checks,
              portable ? "M9_PARSE_PORTABLE: 0 expected" : "most expected");
    checks++;
    if (portable ? hits != 0 : hits < checks / 2) { bad++; printf ("FAIL %s\n", what); }
    printf ("%s\n", what);
  }

  /* speed, printed: a million %.17g strings, strtod against m9_strtod */
  {
    int N = 1000000;
    char *strs = malloc ((size_t) N * 32);
    volatile double sink = 0;
    for (int i = 0; i < N; i++) {
      double v = (double) (int64_t) (rnd () % 2000000000ull) * 1e-7 * (1 + (int) (rnd () % 1000));
      snprintf (strs + (size_t) i * 32, 32, "%.17g", v);
    }
    double t0 = now ();
    for (int i = 0; i < N; i++) sink += strtod (strs + (size_t) i * 32, NULL);
    double t1 = now ();
    for (int i = 0; i < N; i++) sink += m9_strtod (strs + (size_t) i * 32);
    double t2 = now ();
    printf ("a million %%.17g values: strtod %.0f ns each, m9_strtod %.0f ns each\n", (t1 - t0) * 1e3, (t2 - t1) * 1e3);
    (void) sink;
    free (strs);
  }
  if (bad) { printf ("parsef64_driver: %ld of %ld checks FAIL\n", bad, checks); return 1; }
  printf ("parsef64_driver: %ld checks ok\n", checks);
  return 0;
}
